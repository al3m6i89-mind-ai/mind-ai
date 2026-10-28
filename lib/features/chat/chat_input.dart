import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';

/// Rounded Dola-style input bar with image attach and a gradient send button.
class ChatInput extends StatefulWidget {
  const ChatInput({super.key, required this.onSend, this.busy = false, this.hint = 'اسألني أي شيء، أو اكتب "ارسم…"'});

  final void Function(String text, Uint8List? image) onSend;
  final bool busy;
  final String hint;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _c = TextEditingController();
  Uint8List? _image;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
    if (x != null) {
      final b = await x.readAsBytes();
      setState(() => _image = b);
    }
  }

  void _send() {
    if (widget.busy) return;
    final t = _c.text;
    if (t.trim().isEmpty && _image == null) return;
    widget.onSend(t, _image);
    _c.clear();
    setState(() => _image = null);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = Theme.of(context).cardTheme.color;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(color: MindColors.violet.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6))],
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_image != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(_image!, width: 64, height: 64, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          child: GestureDetector(
                            onTap: () => setState(() => _image = null),
                            child: const CircleAvatar(radius: 10, child: Icon(Icons.close, size: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined, color: MindColors.violet),
                    onPressed: _pick,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _c,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MindColors.brand),
                      child: widget.busy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
