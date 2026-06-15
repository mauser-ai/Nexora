import 'brand_bootstrap_cache_model.dart';
import 'brand_bootstrap_cache_stub.dart'
    if (dart.library.html) 'brand_bootstrap_cache_web.dart' as impl;

Future<CachedBrandTheme?> loadCachedBrandTheme() => impl.loadCachedBrandTheme();

Future<void> saveCachedBrandTheme(CachedBrandTheme theme) =>
    impl.saveCachedBrandTheme(theme);

Future<void> clearCachedBrandTheme() => impl.clearCachedBrandTheme();
