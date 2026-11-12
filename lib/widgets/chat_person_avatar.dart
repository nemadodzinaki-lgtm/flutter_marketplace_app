import 'package:flutter/material.dart';

/// Small profile image with a friendly fallback if no photo was uploaded
/// or if the Storage URL no longer works.
class ChatPersonAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const ChatPersonAvatar({super.key, this.imageUrl, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    final fallback = ColoredBox(
      color: const Color(0xFFE5F4E9),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          color: const Color(0xFF16803C),
          size: size * 0.55,
        ),
      ),
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.startsWith('https://')
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}
