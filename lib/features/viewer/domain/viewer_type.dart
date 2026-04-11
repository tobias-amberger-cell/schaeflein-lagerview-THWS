enum ViewerType {
  nativePlaceholder,
  unity,
  webView,
}

extension ViewerTypeLabel on ViewerType {
  String get labelKey {
    switch (this) {
      case ViewerType.nativePlaceholder:
        return 'viewerTypeNative';
      case ViewerType.unity:
        return 'viewerTypeUnity';
      case ViewerType.webView:
        return 'viewerTypeWebView';
    }
  }

  String get descriptionKey {
    switch (this) {
      case ViewerType.nativePlaceholder:
        return 'viewerTypeNativeDesc';
      case ViewerType.unity:
        return 'viewerTypeUnityDesc';
      case ViewerType.webView:
        return 'viewerTypeWebViewDesc';
    }
  }
}
