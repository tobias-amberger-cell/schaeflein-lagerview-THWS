import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_unity_widget/flutter_unity_widget.dart';

Widget buildUnityRuntimeView(BuildContext context, String scenePath) {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Unity Runtime unterstuetzt hier nur Android/iOS.\nQuelle: $scenePath',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  // Der Unity-Export muss als unityLibrary in Android/iOS eingebunden sein.
  // Ohne Export startet das Widget, zeigt aber keine Szene an.
  return UnityWidget(
    onUnityCreated: (UnityWidgetController controller) {
      // Controller wird spaeter fuer Scene/Message-Steuerung genutzt.
    },
  );
}
