enum ArchiveIntegrationProvider { googleDrive, dropbox }

extension ArchiveIntegrationProviderX on ArchiveIntegrationProvider {
  String get key => switch (this) {
    ArchiveIntegrationProvider.googleDrive => 'google_drive',
    ArchiveIntegrationProvider.dropbox => 'dropbox',
  };

  String get label => switch (this) {
    ArchiveIntegrationProvider.googleDrive => 'Drive',
    ArchiveIntegrationProvider.dropbox => 'Dropbox',
  };

  String get fullLabel => switch (this) {
    ArchiveIntegrationProvider.googleDrive => 'Google Drive',
    ArchiveIntegrationProvider.dropbox => 'Dropbox',
  };
}

class ArchiveIntegrationsState {
  const ArchiveIntegrationsState({
    this.googleDriveConnected = false,
    this.dropboxConnected = false,
  });

  final bool googleDriveConnected;
  final bool dropboxConnected;

  bool isConnected(ArchiveIntegrationProvider provider) => switch (provider) {
    ArchiveIntegrationProvider.googleDrive => googleDriveConnected,
    ArchiveIntegrationProvider.dropbox => dropboxConnected,
  };

  ArchiveIntegrationsState copyWith({
    bool? googleDriveConnected,
    bool? dropboxConnected,
  }) {
    return ArchiveIntegrationsState(
      googleDriveConnected: googleDriveConnected ?? this.googleDriveConnected,
      dropboxConnected: dropboxConnected ?? this.dropboxConnected,
    );
  }

  Map<String, dynamic> toJson() => {
    'googleDriveConnected': googleDriveConnected,
    'dropboxConnected': dropboxConnected,
  };

  factory ArchiveIntegrationsState.fromJson(Map<String, dynamic>? json) {
    return ArchiveIntegrationsState(
      googleDriveConnected: json?['googleDriveConnected'] == true,
      dropboxConnected: json?['dropboxConnected'] == true,
    );
  }
}
