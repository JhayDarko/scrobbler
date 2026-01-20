class Scrobble {
  final int? id;
  final String track;
  final String artist;
  final String album;
  final int duration; // en milisegundos
  final DateTime timestamp;
  final int isSynced;

  Scrobble({
    this.id,
    required this.track,
    required this.artist,
    required this.album,
    required this.duration,
    required this.timestamp,
    this.isSynced = 0,
  });

  // Convertir a Map para insertar en DB
  Map<String, dynamic> toMap() {
    return {
      'track': track,
      'artist': artist,
      'album': album,
      'duration': duration,
      'timestamp': timestamp.toIso8601String(),
      'is_synced': isSynced,
    };
  }

  // Crear instancia desde Map de DB
  factory Scrobble.fromMap(Map<String, dynamic> map) {
    return Scrobble(
      id: map['id'] as int?,
      track: map['track'] as String,
      artist: map['artist'] as String,
      album: map['album'] as String,
      duration: map['duration'] as int,
      timestamp: DateTime.parse(map['timestamp'] as String),
      isSynced: map['is_synced'] as int,
    );
  }

  // Crear copia con cambios
  Scrobble copyWith({
    int? id,
    String? track,
    String? artist,
    String? album,
    int? duration,
    DateTime? timestamp,
    int? isSynced,
  }) {
    return Scrobble(
      id: id ?? this.id,
      track: track ?? this.track,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      timestamp: timestamp ?? this.timestamp,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  // Formatear duración en formato MM:SS
  String get formattedDuration {
    if (duration == 0) return '--:--';
    final seconds = duration ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'Scrobble(id: $id, track: $track, artist: $artist, album: $album, duration: $formattedDuration, synced: ${isSynced == 1})';
  }
}
