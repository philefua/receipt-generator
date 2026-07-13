class BusinessSettings {
  String businessName;
  String address;
  String whatsapp;
  String website;
  String instagram;
  String facebook;
  String footnote;
  String currencySymbol;
  String managerPassword;

  BusinessSettings({
    this.businessName = "Printiverse",
    this.address = "Benin City, Edo State, Nigeria",
    this.whatsapp = "",
    this.website = "",
    this.instagram = "",
    this.facebook = "",
    this.footnote = "Thank you for your patronage!",
    this.currencySymbol = "₦",
    this.managerPassword = "admin", // Default password
  });
}
