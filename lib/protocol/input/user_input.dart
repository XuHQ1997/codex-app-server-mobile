/// Input items the client SENDS with `turn/start` / `turn/steer`.
///
/// Mirrors the app-server `UserInput` enum (tagged by camelCase `type`):
/// Text, Image, LocalImage, Skill, Mention.
library;

sealed class UserInput {
  const UserInput();

  Map<String, dynamic> toJson();
}

class TextInput extends UserInput {
  const TextInput(this.text);
  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'text': text};
}

/// A remote image URL.
class ImageInput extends UserInput {
  const ImageInput(this.url, {this.detail});
  final String url;
  final String? detail;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'image',
    'url': url,
    if (detail != null) 'detail': detail,
  };
}

/// A local image file path on the SERVER's filesystem.
class LocalImageInput extends UserInput {
  const LocalImageInput(this.path, {this.detail});
  final String path;
  final String? detail;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'localImage',
    'path': path,
    if (detail != null) 'detail': detail,
  };
}

/// Invoke a skill; pair with a `$name` marker in the text input.
class SkillInput extends UserInput {
  const SkillInput({required this.name, required this.path});
  final String name;
  final String path;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'skill',
    'name': name,
    'path': path,
  };
}

/// A file/app mention; e.g. `app://demo-app`.
class MentionInput extends UserInput {
  const MentionInput({required this.name, required this.path});
  final String name;
  final String path;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'mention',
    'name': name,
    'path': path,
  };
}
