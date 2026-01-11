class StoryPart {
  final String name;
  final String pdf;
  final List<String> audio;

  StoryPart({
    required this.name,
    required this.pdf,
    required this.audio,
  });

  factory StoryPart.fromYaml(Map yaml) {
    final name = yaml['name'];
    final pdf = yaml['pdf'];
    final audio = yaml['audio'];

    if (name == null || name is! String) {
      throw FormatException('StoryPart missing required "name" field or invalid type');
    }
    if (pdf == null || pdf is! String) {
      throw FormatException('StoryPart missing required "pdf" field or invalid type');
    }
    if (audio == null || audio is! List) {
      throw FormatException('StoryPart missing required "audio" field or invalid type');
    }

    return StoryPart(
      name: name,
      pdf: pdf,
      audio: audio.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList(),
    );
  }
}

class StoryCollection {
  final String name;
  final List<StoryPart> parts;

  StoryCollection({
    required this.name,
    required this.parts,
  });

  factory StoryCollection.fromYaml(Map yaml) {
    final name = yaml['name'];
    final parts = yaml['parts'];

    if (name == null || name is! String) {
      throw FormatException('StoryCollection missing required "name" field or invalid type');
    }
    if (parts == null || parts is! List) {
      throw FormatException('StoryCollection missing required "parts" field or invalid type');
    }

    return StoryCollection(
      name: name,
      parts: parts
          .whereType<Map>()
          .map((p) => StoryPart.fromYaml(p))
          .toList(),
    );
  }
}

class StoryManifest {
  final String filePath;
  final String basePath;
  final List<StoryCollection> collections;

  StoryManifest({
    required this.filePath,
    required this.basePath,
    required this.collections,
  });
}
