enum DownloadConcurrencyLimit {
  one('1 at a time', 1),
  two('2 at a time', 2),
  three('3 at a time', 3),
  unlimited('Unlimited', null);

  const DownloadConcurrencyLimit(this.label, this.maxConcurrent);

  final String label;
  final int? maxConcurrent;

  static DownloadConcurrencyLimit byName(String? name) {
    for (final limit in values) {
      if (limit.name == name) return limit;
    }
    return DownloadConcurrencyLimit.one;
  }
}
