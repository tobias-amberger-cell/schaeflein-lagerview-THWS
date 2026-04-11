import '../data/adapters/native_placeholder_viewer_adapter.dart';
import '../data/adapters/unity_viewer_adapter.dart';
import '../data/adapters/webview_viewer_adapter.dart';
import 'viewer_adapter.dart';
import 'viewer_type.dart';

class ViewerAdapterFactory {
  const ViewerAdapterFactory._();

  static ViewerAdapter create(ViewerType type) {
    switch (type) {
      case ViewerType.nativePlaceholder:
        return NativePlaceholderViewerAdapter();
      case ViewerType.unity:
        return UnityViewerAdapter();
      case ViewerType.webView:
        return WebViewViewerAdapter();
    }
  }
}
