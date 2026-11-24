import 'balance_math.dart';

/// Phase 6 (handoff 5.5): finds old "typed text" balance receipts, links them
/// to the original sale when that is clean and unambiguous, and lists the rest
/// for the manager. Pure Dart: no Hive, no Flutter, so it is easy to test.
///
/// What it never does:
///  - change a receipt (links live in the receipt_links box),
///  - accept a fuzzy match on its own (typos become suggestions only),
///  - drop a balance receipt silently (every one ends up linked or listed).

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/// A receipt as the resolver sees it (built from a Hive Receipt elsewhere).
class LegacyReceiptRecord {
  final String code;
  final DateTime issuedAt;

  /// True for phase 5 balance receipts (receiptType == balance_payment).
  final bool isBalanceType;

  /// For phase 5 balance receipts: the original sale code.
  final String? linkedCode;
  final String customerName;
  final String customerWhatsapp;
  final List<String> itemNames;
  final String couponReference;
  final int totalMinor;
  final int depositMinor;

  const LegacyReceiptRecord({
    required this.code,
    required this.issuedAt,
    this.isBalanceType = false,
    this.linkedCode,
    this.customerName = '',
    this.customerWhatsapp = '',
    this.itemNames = const [],
    this.couponReference = '',
    required this.totalMinor,
    required this.depositMinor,
  });
}

/// An active (not voided) manual link from the receipt_links box.
class ManualLinkRecord {
  final String id;

  /// The legacy balance receipt.
  final String receiptCode;

  /// The original sale it pays towards.
  final String originalCode;

  /// Amount applied to the original balance.
  final int appliedMinor;

  const ManualLinkRecord({
    required this.id,
    required this.receiptCode,
    required this.originalCode,
    required this.appliedMinor,
  });
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

enum LegacyStatus { linkedAuto, linkedManual, needsReview }

enum ReviewReason {
  /// Says "balance" but no receipt number could be found in the text.
  noReference,

  /// A receipt number was found but no sale has it (typo?).
  notFound,

  /// The text names the receipt itself.
  selfReference,

  /// More than one receipt number in the text.
  multipleReferences,

  /// Points at another balance receipt that could not be traced to a sale.
  brokenChain,

  /// Balance payment plus new items on one receipt: the manager must say how
  /// much went to the old balance.
  mixedReceipt,

  /// The receipt records no money received.
  noAmount,

  /// The amount is more than the original still owed.
  exceedsBalance,
}

extension ReviewReasonText on ReviewReason {
  String get label {
    switch (this) {
      case ReviewReason.noReference:
        return 'No receipt number found in the text';
      case ReviewReason.notFound:
        return 'The receipt number does not match any sale';
      case ReviewReason.selfReference:
        return 'The text points back at this same receipt';
      case ReviewReason.multipleReferences:
        return 'More than one receipt number in the text';
      case ReviewReason.brokenChain:
        return 'Points at another balance receipt that is not linked yet';
      case ReviewReason.mixedReceipt:
        return 'Also sold new items: enter how much paid the old balance';
      case ReviewReason.noAmount:
        return 'No payment amount is recorded on this receipt';
      case ReviewReason.exceedsBalance:
        return 'The amount is more than the original still owed';
    }
  }
}

/// A sale the manager may want to link to. Never applied automatically.
class LegacySuggestion {
  final String code;
  final String customerName;
  final DateTime issuedAt;
  final int totalMinor;

  /// What the sale still owes right now.
  final int outstandingMinor;
  final int score;
  final List<String> reasons;

  const LegacySuggestion({
    required this.code,
    required this.customerName,
    required this.issuedAt,
    required this.totalMinor,
    required this.outstandingMinor,
    required this.score,
    required this.reasons,
  });
}

class LegacyBalanceEntry {
  final String code;
  final DateTime issuedAt;
  final String customerName;
  final int totalMinor;

  /// Money received on this receipt.
  final int paidMinor;

  /// The text the matcher read (item names and coupon field).
  final String textSnippet;

  /// Receipt numbers found in the text.
  final List<String> referencesFound;
  final LegacyStatus status;
  final ReviewReason? reason;

  /// The original sale, when known (linked, or known but needs an amount).
  final String? originalCode;

  /// Amount applied to the original balance (linked entries only).
  final int appliedMinor;

  /// Pre-filled amount for the manager when it differs from [paidMinor].
  final int? suggestedAppliedMinor;
  final List<LegacySuggestion> suggestions;

  /// Id of the manual link, when [status] is linkedManual.
  final String? manualLinkId;

  /// True when the receipt also sold new items besides the old balance.
  final bool isMixed;

  const LegacyBalanceEntry({
    required this.code,
    required this.issuedAt,
    required this.customerName,
    required this.totalMinor,
    required this.paidMinor,
    required this.textSnippet,
    required this.referencesFound,
    required this.status,
    this.reason,
    this.originalCode,
    this.appliedMinor = 0,
    this.suggestedAppliedMinor,
    this.suggestions = const [],
    this.manualLinkId,
    this.isMixed = false,
  });

  bool get isLinked => status != LegacyStatus.needsReview;
}

class LegacyResolution {
  /// Every legacy balance receipt, newest first.
  final List<LegacyBalanceEntry> entries;

  /// Outstanding per sale before any legacy payment is applied
  /// (total - deposit - phase 5 balance receipts), never below zero.
  final Map<String, int> baseOutstanding;

  const LegacyResolution({
    required this.entries,
    required this.baseOutstanding,
  });

  List<LegacyBalanceEntry> get needsReview =>
      [for (final e in entries) if (!e.isLinked) e];

  List<LegacyBalanceEntry> get linked =>
      [for (final e in entries) if (e.isLinked) e];

  int get needsReviewCount => entries.where((e) => !e.isLinked).length;

  /// Linked legacy payments in the shape [BalanceMath] already uses. Add these
  /// to the phase 5 payments to get the true outstanding per sale. The legacy
  /// receipts themselves must not be counted as sales in reports (phase 9).
  List<PaymentSummary> get payments => [
        for (final e in entries)
          if (e.isLinked && e.originalCode != null && e.appliedMinor > 0)
            PaymentSummary(
                linkedCode: e.originalCode!, amountMinor: e.appliedMinor),
      ];

  /// Codes of every linked legacy balance receipt.
  Set<String> get linkedCodes => {for (final e in entries) if (e.isLinked) e.code};

  /// Linked legacy receipts that only paid an old balance. Whatever they show
  /// as "owed" is the same money that is still owed on the original sale, so
  /// they must not count as a second debt. Mixed receipts are left alone: the
  /// new items on them can genuinely be unpaid.
  Set<String> get ownBalanceCleared =>
      {for (final e in entries) if (e.isLinked && !e.isMixed) e.code};

  /// What [originalCode] still owes if the legacy receipt [exceptCode] were
  /// not applied to it. Used to check a manual link.
  int remainingExcluding(String originalCode, String exceptCode) {
    var left = baseOutstanding[originalCode] ?? 0;
    for (final e in entries) {
      if (e.isLinked && e.originalCode == originalCode && e.code != exceptCode) {
        left -= e.appliedMinor;
      }
    }
    return left < 0 ? 0 : left;
  }
}

// ---------------------------------------------------------------------------
// Resolver
// ---------------------------------------------------------------------------

class _Cand {
  final LegacyReceiptRecord rec;
  final List<String> tokens;
  final bool mixed;
  final ManualLinkRecord? manual;
  _Cand(this.rec, this.tokens, this.mixed, this.manual);
}

class _Origin {
  final String? original;
  final ReviewReason? failure;
  const _Origin.ok(String this.original) : failure = null;
  const _Origin.fail(ReviewReason this.failure) : original = null;
}

class LegacyBalanceResolver {
  LegacyBalanceResolver._();

  /// Receipt numbers look like ZKq01: year letter, month letter A-L, day
  /// letter (a-z for 1-26, A-E for 27-31), two-digit serial. Phase 5 balance
  /// receipts add "-B".
  static final RegExp _strictToken = RegExp(
      r'(?<![A-Za-z0-9])[A-Z][A-L][a-zA-E]\d{2}(?:-B)?(?![A-Za-z0-9])');

  /// Used only when no strict token exists, to catch typos such as "zkq01",
  /// "ZKq1" or "ZKq001".
  static final RegExp _looseToken =
      RegExp(r'(?<![A-Za-z0-9])[A-Za-z]{3}\d{1,3}(?:-[Bb])?(?![A-Za-z0-9])');

  /// Words that mark a legacy balance payment. Tune here if real receipts use
  /// other wording.
  static final RegExp _keyword = RegExp(
      r'(?<![A-Za-z])(?:bal|bal+an[cs]e|balence|outstanding|part[\s-]?payment)(?![A-Za-z])',
      caseSensitive: false);

  static List<String> _distinct(Iterable<String> xs) {
    final seen = <String>{};
    return [for (final x in xs) if (seen.add(x)) x];
  }

  static List<String> _texts(LegacyReceiptRecord r) => [
        ...r.itemNames,
        if (r.couponReference.trim().isNotEmpty) r.couponReference,
      ];

  static bool _hasKeyword(LegacyReceiptRecord r) =>
      _texts(r).any(_keyword.hasMatch);

  /// An item that is essentially just the number of an existing receipt
  /// (for example "ZKx01" or "Item-ZKx01"), typed as the whole item with no
  /// balance wording. The number must belong to a different, existing receipt,
  /// so this is a very strong sign of an old balance payment.
  static bool _isBareReference(
      LegacyReceiptRecord r, Map<String, LegacyReceiptRecord> byCode) {
    for (final text in _texts(r)) {
      for (final m in _strictToken.allMatches(text)) {
        final code = m.group(0)!;
        if (code == r.code || !byCode.containsKey(code)) continue;
        final rest = text.replaceRange(m.start, m.end, ' ');
        final words = RegExp(r'[A-Za-z0-9]+').allMatches(rest).length;
        if (words <= 1) return true;
      }
    }
    return false;
  }

  static List<String> _tokensIn(LegacyReceiptRecord r) {
    final texts = _texts(r);
    final strict = _distinct([
      for (final t in texts)
        for (final m in _strictToken.allMatches(t)) m.group(0)!,
    ]);
    if (strict.isNotEmpty) return strict;
    return _distinct([
      for (final t in texts)
        for (final m in _looseToken.allMatches(t)) m.group(0)!,
    ]);
  }

  static bool _isMixed(LegacyReceiptRecord r, List<String> tokens) {
    if (r.itemNames.length <= 1) return false;
    return r.itemNames.any((name) {
      if (_keyword.hasMatch(name)) return false;
      if (tokens.any(name.contains)) return false;
      return true;
    });
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String _baseCode(String s) {
    final up = s.toUpperCase();
    return up.endsWith('-B') ? s.substring(0, s.length - 2) : s;
  }

  /// Optimal string alignment distance (insert, delete, replace, swap).
  static int _distance(String a, String b) {
    final d = List.generate(
        a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = d[i - 1][j] + 1;
        if (d[i][j - 1] + 1 < v) v = d[i][j - 1] + 1;
        if (d[i - 1][j - 1] + cost < v) v = d[i - 1][j - 1] + cost;
        if (i > 1 &&
            j > 1 &&
            a[i - 1] == b[j - 2] &&
            a[i - 2] == b[j - 1] &&
            d[i - 2][j - 2] + 1 < v) {
          v = d[i - 2][j - 2] + 1;
        }
        d[i][j] = v;
      }
    }
    return d[a.length][b.length];
  }

  // -------------------------------------------------------------------------

  static LegacyResolution resolve({
    required List<LegacyReceiptRecord> receipts,
    required List<ManualLinkRecord> manualLinks,

    /// Amounts the manager has written off per sale ("Settle with
    /// adjustment"). They reduce what a sale can still be paid.
    Map<String, int> writeoffs = const {},
  }) {
    final byCode = <String, LegacyReceiptRecord>{
      for (final r in receipts) r.code: r,
    };

    // Latest active manual link per legacy receipt.
    final manualByReceipt = <String, ManualLinkRecord>{
      for (final l in manualLinks) l.receiptCode: l,
    };

    // Candidates: sale-type receipts that say "balance", plus any receipt the
    // manager has linked by hand.
    final cands = <String, _Cand>{};
    for (final r in receipts) {
      if (r.isBalanceType) continue;
      final manual = manualByReceipt[r.code];
      if (!_hasKeyword(r) && manual == null && !_isBareReference(r, byCode)) {
        continue;
      }
      final tokens = _tokensIn(r);
      cands[r.code] = _Cand(r, tokens, _isMixed(r, tokens), manual);
    }

    // Outstanding per sale before legacy payments.
    final phase5Paid = <String, int>{};
    for (final r in receipts) {
      if (r.isBalanceType && r.linkedCode != null) {
        phase5Paid[r.linkedCode!] =
            (phase5Paid[r.linkedCode!] ?? 0) + r.totalMinor;
      }
    }
    final base = <String, int>{
      for (final r in receipts)
        if (!r.isBalanceType)
          r.code: BalanceMath.outstandingMinor(
            totalMinor: r.totalMinor,
            depositMinor: r.depositMinor,
            paidLaterMinor:
                (phase5Paid[r.code] ?? 0) + (writeoffs[r.code] ?? 0),
          ),
    };

    // ---- 1. Which sale does each candidate point at? ----
    final memo = <String, _Origin>{};
    _Origin originOf(String code, Set<String> visiting) {
      final cached = memo[code];
      if (cached != null) return cached;
      if (!visiting.add(code)) {
        return const _Origin.fail(ReviewReason.brokenChain);
      }
      final c = cands[code]!;
      _Origin result;

      _Origin viaTarget(LegacyReceiptRecord? target) {
        if (target == null) return const _Origin.fail(ReviewReason.notFound);
        if (target.code == code) {
          return const _Origin.fail(ReviewReason.selfReference);
        }
        if (target.isBalanceType) {
          // Phase 5 balance receipt: follow its structured link.
          final up = target.linkedCode == null ? null : byCode[target.linkedCode!];
          if (up == null || up.isBalanceType || cands.containsKey(up.code)) {
            return const _Origin.fail(ReviewReason.brokenChain);
          }
          return _Origin.ok(up.code);
        }
        if (cands.containsKey(target.code)) {
          // Another legacy balance receipt: follow the chain.
          final sub = originOf(target.code, visiting);
          return sub.failure != null
              ? const _Origin.fail(ReviewReason.brokenChain)
              : _Origin.ok(sub.original!);
        }
        return _Origin.ok(target.code);
      }

      if (c.manual != null) {
        final target = byCode[c.manual!.originalCode];
        final bad = target == null ||
            target.isBalanceType ||
            cands.containsKey(target.code) ||
            target.code == code;
        result = bad
            ? const _Origin.fail(ReviewReason.notFound)
            : _Origin.ok(target.code);
      } else if (c.tokens.isEmpty) {
        result = const _Origin.fail(ReviewReason.noReference);
      } else if (c.tokens.length > 1) {
        result = const _Origin.fail(ReviewReason.multipleReferences);
      } else {
        result = viaTarget(byCode[c.tokens.first]);
      }
      visiting.remove(code);
      memo[code] = result;
      return result;
    }

    final origins = <String, _Origin>{
      for (final code in cands.keys) code: originOf(code, <String>{}),
    };

    // ---- 2. Apply amounts: manual links first, then the rest oldest first ----
    final remaining = Map<String, int>.from(base);
    final decided = <String, LegacyBalanceEntry>{};
    final pending = <String, _Pending>{};

    LegacyBalanceEntry entry(
      _Cand c, {
      required LegacyStatus status,
      ReviewReason? reason,
      String? original,
      int applied = 0,
      int? suggestedApplied,
      String? manualId,
    }) =>
        LegacyBalanceEntry(
          code: c.rec.code,
          issuedAt: c.rec.issuedAt,
          customerName: c.rec.customerName,
          totalMinor: c.rec.totalMinor,
          paidMinor: c.rec.depositMinor,
          textSnippet: _texts(c.rec).join(' | '),
          referencesFound: c.tokens,
          status: status,
          reason: reason,
          originalCode: original,
          appliedMinor: applied,
          suggestedAppliedMinor: suggestedApplied,
          manualLinkId: manualId,
          isMixed: c.mixed,
        );

    final ordered = cands.values.toList()
      ..sort((a, b) {
        final byDate = a.rec.issuedAt.compareTo(b.rec.issuedAt);
        return byDate != 0 ? byDate : a.rec.code.compareTo(b.rec.code);
      });

    // Manual links are authoritative: they take their share first.
    for (final c in ordered) {
      final m = c.manual;
      if (m == null) continue;
      final o = origins[c.rec.code]!;
      if (o.failure != null) {
        pending[c.rec.code] = _Pending(c, o.failure!, null, null);
        continue;
      }
      final left = remaining[o.original!] ?? 0;
      remaining[o.original!] = left - m.appliedMinor < 0 ? 0 : left - m.appliedMinor;
      decided[c.rec.code] = entry(c,
          status: LegacyStatus.linkedManual,
          original: o.original,
          applied: m.appliedMinor,
          manualId: m.id);
    }

    for (final c in ordered) {
      if (c.manual != null) continue;
      final o = origins[c.rec.code]!;
      if (o.failure != null) {
        pending[c.rec.code] = _Pending(c, o.failure!, null, null);
        continue;
      }
      final original = o.original!;
      final left = remaining[original] ?? 0;
      if (c.mixed) {
        pending[c.rec.code] =
            _Pending(c, ReviewReason.mixedReceipt, original, null);
        continue;
      }
      final amount = c.rec.depositMinor;
      if (amount <= 0) {
        pending[c.rec.code] =
            _Pending(c, ReviewReason.noAmount, original, null);
        continue;
      }
      if (amount > left) {
        pending[c.rec.code] = _Pending(
            c, ReviewReason.exceedsBalance, original, left > 0 ? left : null);
        continue;
      }
      remaining[original] = left - amount;
      decided[c.rec.code] = entry(c,
          status: LegacyStatus.linkedAuto, original: original, applied: amount);
    }

    // ---- 3. Suggestions, using the final outstanding ----
    for (final p in pending.values) {
      final c = p.cand;
      final showSuggestions = p.original == null ||
          p.reason == ReviewReason.exceedsBalance;
      final suggestions = (p.original == null && showSuggestions)
          ? _suggest(c, receipts, cands, remaining, byCode)
          : const <LegacySuggestion>[];
      decided[c.rec.code] = LegacyBalanceEntry(
        code: c.rec.code,
        issuedAt: c.rec.issuedAt,
        customerName: c.rec.customerName,
        totalMinor: c.rec.totalMinor,
        paidMinor: c.rec.depositMinor,
        textSnippet: _texts(c.rec).join(' | '),
        referencesFound: c.tokens,
        status: LegacyStatus.needsReview,
        reason: p.reason,
        originalCode: p.original,
        suggestedAppliedMinor: p.suggestedApplied,
        suggestions: suggestions,
        isMixed: c.mixed,
      );
    }

    final entries = decided.values.toList()
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return LegacyResolution(entries: entries, baseOutstanding: base);
  }

  static List<LegacySuggestion> _suggest(
    _Cand c,
    List<LegacyReceiptRecord> receipts,
    Map<String, _Cand> cands,
    Map<String, int> remaining,
    Map<String, LegacyReceiptRecord> byCode,
  ) {
    final paid = c.rec.depositMinor;
    final name = _norm(c.rec.customerName);
    final phone = _digits(c.rec.customerWhatsapp);
    final typed = c.tokens.map(_baseCode).toList();

    // Sales that are named in the text (used when there are several).
    final named = <String>{};
    for (final t in c.tokens) {
      final target = byCode[t];
      if (target != null && !target.isBalanceType && !cands.containsKey(t)) {
        named.add(t);
      }
    }

    final out = <LegacySuggestion>[];
    for (final s in receipts) {
      if (s.isBalanceType || s.code == c.rec.code) continue;
      if (cands.containsKey(s.code)) continue;
      if (s.issuedAt.isAfter(c.rec.issuedAt)) continue;
      final owed = remaining[s.code] ?? 0;
      if (owed <= 0) continue;

      var score = 0;
      final why = <String>[];

      if (named.contains(s.code)) {
        score += 8;
        why.add('Number written on this receipt');
      } else {
        var best = 99;
        var caseOnly = false;
        for (final t in typed) {
          if (t.toLowerCase() == s.code.toLowerCase() && t != s.code) {
            caseOnly = true;
          }
          final d = _distance(t, s.code);
          if (d < best) best = d;
        }
        if (caseOnly) {
          score += 6;
          why.add('Same letters, different capitals');
        } else if (best == 1) {
          score += 5;
          why.add('Number differs by one character');
        } else if (best == 2) {
          score += 3;
          why.add('Number differs by two characters');
        }
      }

      final sameName = name.isNotEmpty && _norm(s.customerName) == name;
      final samePhone = phone.length >= 8 && _digits(s.customerWhatsapp) == phone;
      if (sameName || samePhone) {
        score += 4;
        why.add('Same customer');
      }

      if (score > 0 && paid > 0) {
        if (paid == owed) {
          score += 3;
          why.add('Amount paid equals the balance owed');
        } else if (paid < owed) {
          score += 1;
        }
      }

      if (score < 4) continue;
      out.add(LegacySuggestion(
        code: s.code,
        customerName: s.customerName,
        issuedAt: s.issuedAt,
        totalMinor: s.totalMinor,
        outstandingMinor: owed,
        score: score,
        reasons: why,
      ));
    }
    out.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : b.issuedAt.compareTo(a.issuedAt);
    });
    return out.take(5).toList();
  }

  // -------------------------------------------------------------------------

  /// Plain-English problem with a proposed manual link, or null if it is fine.
  static String? validateManualLink({
    required List<LegacyReceiptRecord> receipts,
    required List<ManualLinkRecord> manualLinks,
    required String legacyCode,
    required String originalCode,
    required int appliedMinor,
    Map<String, int> writeoffs = const {},
  }) {
    final byCode = <String, LegacyReceiptRecord>{
      for (final r in receipts) r.code: r,
    };
    final legacy = byCode[legacyCode.trim()];
    if (legacy == null || legacy.isBalanceType) {
      return 'That balance receipt was not found.';
    }
    final code = originalCode.trim();
    if (code.isEmpty) return 'Enter the original sale receipt number.';
    final original = byCode[code];
    if (original == null) {
      return 'No receipt found with the number $code. '
          'Capital and small letters matter.';
    }
    if (original.code == legacy.code) {
      return 'A receipt cannot be linked to itself.';
    }
    if (original.isBalanceType) {
      return '$code is a balance receipt. Enter the original sale receipt.';
    }
    if (original.issuedAt.isAfter(legacy.issuedAt)) {
      return 'The original sale is dated after this balance receipt.';
    }
    if (appliedMinor <= 0) return 'Enter an amount above zero.';
    if (appliedMinor > legacy.depositMinor) {
      return 'The amount cannot be more than the money received on this receipt.';
    }

    final others = [
      for (final l in manualLinks)
        if (l.receiptCode != legacy.code) l,
    ];
    final resolution =
        resolve(receipts: receipts, manualLinks: others, writeoffs: writeoffs);
    final isOtherBalance = resolution.entries.any((e) => e.code == original.code);
    if (isOtherBalance) {
      return '$code is itself a balance receipt. Enter the original sale receipt.';
    }
    final left = resolution.remainingExcluding(original.code, legacy.code);
    if (left <= 0) return '$code has no balance left to pay.';
    if (appliedMinor > left) {
      return 'The amount cannot be more than the balance still owed on $code.';
    }
    return null;
  }
}

class _Pending {
  final _Cand cand;
  final ReviewReason reason;
  final String? original;
  final int? suggestedApplied;
  _Pending(this.cand, this.reason, this.original, this.suggestedApplied);
}
