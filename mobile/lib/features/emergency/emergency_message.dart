class EmergencyMessage {
  const EmergencyMessage({
    required this.contactId,
    required this.contactName,
    required this.whatsapp,
    required this.message,
    required this.waUrl,
  });

  final String contactId;
  final String contactName;
  final String whatsapp;
  final String message;
  final String waUrl;

  factory EmergencyMessage.fromJson(Map<String, dynamic> json) {
    return EmergencyMessage(
      contactId: json['contactId'] as String,
      contactName: json['contactName'] as String,
      whatsapp: json['whatsapp'] as String,
      message: json['message'] as String,
      waUrl: json['waUrl'] as String,
    );
  }
}
