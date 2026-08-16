import 'package:flutter/material.dart';

class GuideItem {
  const GuideItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.version,
  });

  final IconData icon;
  final String title;
  final String description;
  final int version;
}
