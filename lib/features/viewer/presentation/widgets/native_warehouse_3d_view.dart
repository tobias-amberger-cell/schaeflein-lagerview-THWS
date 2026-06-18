import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../models/viewer_heatmap.dart';
import '../../../../models/warehouse_heatmap_layer.dart';
import '../../../../models/warehouse.dart';

class NativeWarehouse3DView extends StatefulWidget {
  const NativeWarehouse3DView({
    super.key,
    required this.warehouse,
    required this.model,
    required this.tourRunning,
    required this.zonesVisible,
    required this.heatmapVisible,
    required this.heatmapMetric,
    required this.heatmapData,
    this.warehouseHeatmapLayer = const <WarehouseHeatmapLayerEntry>[],
    this.focusZoneName,
    this.focusRequestId = 0,
    this.focusRackNumber,
    this.focusLevelNumber,
    this.focusSlotNumber,
    this.focusLocationRequestId = 0,
    this.enableFirstPersonControls = false,
    this.topOverlayReservedSpace = 0,
    this.bottomOverlayReservedSpace = 0,
    this.cameraToggleBottom = false,
    this.showOperatorPanel = false,
  });

  final Warehouse warehouse;
  final WarehouseModelData? model;
  final bool tourRunning;
  final bool zonesVisible;
  final bool heatmapVisible;
  final ViewerHeatmapMetric heatmapMetric;
  final List<ViewerHeatmapEntry> heatmapData;
  final List<WarehouseHeatmapLayerEntry> warehouseHeatmapLayer;
  final String? focusZoneName;
  final int focusRequestId;
  final int? focusRackNumber;
  final int? focusLevelNumber;
  final int? focusSlotNumber;
  final int focusLocationRequestId;
  final bool enableFirstPersonControls;
  final double topOverlayReservedSpace;
  final double bottomOverlayReservedSpace;
  final bool cameraToggleBottom;
  final bool showOperatorPanel;

  @override
  State<NativeWarehouse3DView> createState() => _NativeWarehouse3DViewState();
}

enum _ViewerCameraMode {
  orbit,
  firstPerson,
}

enum _TraversalMode {
  person,
  fly,
}

enum _TraversalSpeed {
  slow,
  normal,
  sprint,
}

extension _TraversalSpeedX on _TraversalSpeed {
  String get label {
    return switch (this) {
      _TraversalSpeed.slow => 'Langsam',
      _TraversalSpeed.normal => 'Normal',
      _TraversalSpeed.sprint => 'Sprint',
    };
  }

  double get factor {
    return switch (this) {
      _TraversalSpeed.slow => 0.74,
      _TraversalSpeed.normal => 1.0,
      _TraversalSpeed.sprint => 1.42,
    };
  }
}

enum _CameraPreset {
  overall,
  dock,
  aisle,
}

enum _InspectionMarkerType {
  bottleneck,
  safety,
  damage,
}

enum _InspectionStatus {
  open,
  inReview,
  closed,
}

extension _InspectionStatusX on _InspectionStatus {
  String get label {
    return switch (this) {
      _InspectionStatus.open => 'Offen',
      _InspectionStatus.inReview => 'In Prüfung',
      _InspectionStatus.closed => 'Geschlossen',
    };
  }
}

enum _InspectionPriority {
  low,
  medium,
  high,
}

extension _InspectionPriorityX on _InspectionPriority {
  String get label {
    return switch (this) {
      _InspectionPriority.low => 'Niedrig',
      _InspectionPriority.medium => 'Mittel',
      _InspectionPriority.high => 'Hoch',
    };
  }

  int get weight {
    return switch (this) {
      _InspectionPriority.low => 1,
      _InspectionPriority.medium => 2,
      _InspectionPriority.high => 3,
    };
  }
}

extension _InspectionMarkerTypeX on _InspectionMarkerType {
  String get label {
    return switch (this) {
      _InspectionMarkerType.bottleneck => 'Engpass',
      _InspectionMarkerType.safety => 'Sicherheit',
      _InspectionMarkerType.damage => 'Schaden',
    };
  }

  Color color() {
    return switch (this) {
      _InspectionMarkerType.bottleneck => const Color(0xFFF59E0B),
      _InspectionMarkerType.safety => const Color(0xFF0EA5E9),
      _InspectionMarkerType.damage => const Color(0xFFDC2626),
    };
  }
}

class _InspectionMarker {
  const _InspectionMarker({
    required this.id,
    required this.type,
    required this.status,
    required this.priority,
    required this.owner,
    required this.reference,
    required this.forward,
    required this.strafe,
    required this.lift,
    required this.createdAt,
    this.dueDate,
  });

  final String id;
  final _InspectionMarkerType type;
  final _InspectionStatus status;
  final _InspectionPriority priority;
  final String owner;
  final String reference;
  final double forward;
  final double strafe;
  final double lift;
  final DateTime createdAt;
  final DateTime? dueDate;

  _InspectionMarker copyWith({
    _InspectionMarkerType? type,
    _InspectionStatus? status,
    _InspectionPriority? priority,
    String? owner,
    String? reference,
    DateTime? dueDate,
    bool setDueDate = false,
  }) {
    return _InspectionMarker(
      id: id,
      type: type ?? this.type,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      owner: owner ?? this.owner,
      reference: reference ?? this.reference,
      forward: forward,
      strafe: strafe,
      lift: lift,
      createdAt: createdAt,
      dueDate: setDueDate ? dueDate : this.dueDate,
    );
  }
}

enum _ViewerSensitivity {
  slow,
  normal,
  fast,
}

extension _ViewerSensitivityX on _ViewerSensitivity {
  String get label {
    return switch (this) {
      _ViewerSensitivity.slow => 'Langsam',
      _ViewerSensitivity.normal => 'Normal',
      _ViewerSensitivity.fast => 'Schnell',
    };
  }

  double get lookFactor {
    return switch (this) {
      _ViewerSensitivity.slow => 0.76,
      _ViewerSensitivity.normal => 1.0,
      _ViewerSensitivity.fast => 1.34,
    };
  }

  double get moveFactor {
    return switch (this) {
      _ViewerSensitivity.slow => 0.82,
      _ViewerSensitivity.normal => 1.0,
      _ViewerSensitivity.fast => 1.30,
    };
  }

  double get zoomFactor {
    return switch (this) {
      _ViewerSensitivity.slow => 0.82,
      _ViewerSensitivity.normal => 1.0,
      _ViewerSensitivity.fast => 1.22,
    };
  }

  double get cameraSmoothRate {
    return switch (this) {
      _ViewerSensitivity.slow => 7.4,
      _ViewerSensitivity.normal => 9.6,
      _ViewerSensitivity.fast => 12.0,
    };
  }
}

enum _RenderQuality {
  auto,
  quality,
  balanced,
  performance,
}

enum _HeatmapHotspotFilter {
  critical,
  high,
  all,
}

class _NativeWarehouse3DViewState extends State<NativeWarehouse3DView>
    with SingleTickerProviderStateMixin {
  double _manualYaw = 0;
  double _manualPitch = 0;
  double _cameraForward = 0;
  double _cameraStrafe = 0;
  double _cameraLift = 0;
  double _targetYaw = 0;
  double _targetPitch = 0;
  double _targetForward = 0;
  double _targetStrafe = 0;
  double _targetLift = 0;
  Offset _moveInput = Offset.zero;
  Offset _lookInput = Offset.zero;
  Offset _liftInput = Offset.zero;
  Offset _moveInputTarget = Offset.zero;
  Offset _lookInputTarget = Offset.zero;
  Offset _liftInputTarget = Offset.zero;
  double _forwardVelocity = 0;
  double _strafeVelocity = 0;
  double _liftVelocity = 0;
  double _lookYawVelocity = 0;
  double _lookPitchVelocity = 0;
  Offset _smoothedGestureFocalDelta = Offset.zero;
  double _lastScale = 1;
  double _smoothedScaleDelta = 1;
  bool _gestureDriveActive = false;
  int _lastGesturePointerCount = 0;
  double _gestureModeBlend = 0;
  double _smoothedPinchForward = 0;
  Offset _smoothedTwoFingerMove = Offset.zero;
  late final Ticker _ticker;
  Duration? _lastTick;
  _ViewerCameraMode _cameraMode = _ViewerCameraMode.orbit;
  _ViewerSensitivity _sensitivity = _ViewerSensitivity.normal;
  bool _isCameraInMotion = false;
  _TraversalMode _traversalMode = _TraversalMode.person;
  _TraversalSpeed _traversalSpeed = _TraversalSpeed.normal;
  bool _precisionMode = false;
  bool _showJoysticks = true;
  bool _showFpHint = false;
  Timer? _fpHintTimer;
  bool _fpHintShownOnce = false;
  final _InspectionMarkerType _selectedMarkerType = _InspectionMarkerType.bottleneck;
  final _InspectionStatus _selectedMarkerStatus = _InspectionStatus.open;
  final _InspectionPriority _selectedMarkerPriority = _InspectionPriority.medium;
  final String _selectedMarkerOwner = 'Team Lager';
  final String _selectedMarkerReference = '';
  final int _selectedDueInDays = 7;
  List<_InspectionMarker> _inspectionMarkers = <_InspectionMarker>[];
  String? _focusedMarkerId;
  final List<Offset> _routeTrail = <Offset>[];
  Duration _lastTrailSample = Duration.zero;
  bool _autoTourRunning = false;
  bool _autoTourUsesCustomWaypoints = false;
  int _autoTourWaypointIndex = 0;
  List<Offset> _autoTourWaypoints = <Offset>[];
  int _autoTourStallTicks = 0;
  final List<Offset> _customTourWaypoints = <Offset>[];
  int _lastHandledFocusRequestId = 0;
  int _lastHandledStorageFocusRequestId = 0;
  String? _focusedZoneName;
  int? _focusedRackNumber;
  int? _focusedLevelNumber;
  int? _focusedSlotNumber;
  _HeatmapRackSelection? _selectedHeatmapSelection;
  double _selectedHeatmapPulseS = 0;
  final List<_HeatmapRackSelection> _recentHeatmapSelections = <_HeatmapRackSelection>[];
  bool _heatmapRackHighlightEnabled = true;
  _HeatmapHotspotFilter _heatmapHotspotFilter = _HeatmapHotspotFilter.high;
  double _focusBoostRemainingS = 0;
  double _focusHighlightRemainingS = 0;
  double _storageFocusPulseS = 0;
  _NavigationGeometry? _cachedNavigationGeometry;
  int? _cachedNavigationGeometryKey;
  // Gang-Breiten-Faktor: zieht die Regalreihen rein visuell weiter auseinander
  // (breitere Wege zum Durchfliegen), ohne Regale/Plaetze selbst zu veraendern.
  // 1.0 = normal. Skaliert die Hallen-Abmessungen; die Regalgroesse wird
  // kompensiert, sodass nur die Gaenge wachsen.
  double _aisleSpread = 1.0;

  int get _availableShelfLevels {
    final fromModel = widget.model?.shelfLevels;
    final fromLayout = widget.warehouse.layoutSpec?.rackLevels;
    return (fromModel ?? fromLayout ?? 3).clamp(1, 12);
  }

  @override
  void initState() {
    super.initState();
    _lastHandledFocusRequestId = widget.focusRequestId;
    _lastHandledStorageFocusRequestId = widget.focusLocationRequestId;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant NativeWarehouse3DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.warehouse != widget.warehouse || oldWidget.model != widget.model) {
      _cachedNavigationGeometry = null;
      _cachedNavigationGeometryKey = null;
      _selectedHeatmapSelection = null;
      _selectedHeatmapPulseS = 0;
      _recentHeatmapSelections.clear();
      _focusedRackNumber = null;
      _focusedLevelNumber = null;
      _focusedSlotNumber = null;
      _storageFocusPulseS = 0;
    }
    if (oldWidget.heatmapVisible != widget.heatmapVisible && !widget.heatmapVisible) {
      _selectedHeatmapSelection = null;
      _selectedHeatmapPulseS = 0;
    }
    if (oldWidget.heatmapMetric != widget.heatmapMetric) {
      _selectedHeatmapSelection = null;
      _selectedHeatmapPulseS = 0;
    }
    final focusRequested = widget.focusRequestId != _lastHandledFocusRequestId;
    if (focusRequested) {
      _lastHandledFocusRequestId = widget.focusRequestId;
      final zoneName = widget.focusZoneName?.trim();
      if (zoneName != null && zoneName.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _focusZoneByName(zoneName);
        });
      }
    }
    final storageFocusRequested =
        widget.focusLocationRequestId != _lastHandledStorageFocusRequestId;
    if (storageFocusRequested) {
      _lastHandledStorageFocusRequestId = widget.focusLocationRequestId;
      _focusedRackNumber = widget.focusRackNumber;
      _focusedLevelNumber = widget.focusLevelNumber;
      _focusedSlotNumber = widget.focusSlotNumber;
      _storageFocusPulseS = 2.4;
    }
  }

  @override
  void dispose() {
    _fpHintTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _triggerFpHint() {
    if (_fpHintShownOnce) {
      return;
    }
    _fpHintShownOnce = true;
    _fpHintTimer?.cancel();
    setState(() {
      _showFpHint = true;
    });
    _fpHintTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showFpHint = false;
      });
    });
  }

  void _onTick(Duration elapsed) {
    final lastTick = _lastTick;
    _lastTick = elapsed;
    if (lastTick == null) {
      return;
    }
    final dt =
        ((elapsed - lastTick).inMicroseconds / 1000000).clamp(0.0, 0.05).toDouble();
    if (dt <= 0) {
      return;
    }
    final hasAutoTarget = _autoTourRunning && _autoTourWaypoints.isNotEmpty;
    final hasInputTarget = hasAutoTarget ||
        _moveInputTarget.distance > 0.0015 ||
        _lookInputTarget.distance > 0.0015 ||
        _liftInputTarget.distance > 0.0015;
    final hasVelocity = _forwardVelocity.abs() > 0.0008 ||
        _strafeVelocity.abs() > 0.0008 ||
        _liftVelocity.abs() > 0.0008 ||
        _lookYawVelocity.abs() > 0.0008 ||
        _lookPitchVelocity.abs() > 0.0008;
    final hasFocusAnimation = _focusBoostRemainingS > 0 ||
        _focusHighlightRemainingS > 0 ||
        _selectedHeatmapPulseS > 0 ||
        _storageFocusPulseS > 0;
    final hasTargetDelta = _angleDelta(_manualYaw, _targetYaw).abs() > 0.0008 ||
        (_manualPitch - _targetPitch).abs() > 0.0008 ||
        (_cameraForward - _targetForward).abs() > 0.0008 ||
        (_cameraStrafe - _targetStrafe).abs() > 0.0008 ||
        (_cameraLift - _targetLift).abs() > 0.0008 ||
        (_moveInput - _moveInputTarget).distance > 0.0008 ||
        (_lookInput - _lookInputTarget).distance > 0.0008 ||
        (_liftInput - _liftInputTarget).distance > 0.0008;

    if (!hasInputTarget && !hasVelocity && !hasTargetDelta && !hasFocusAnimation) {
      return;
    }

    setState(() {
      if (_focusBoostRemainingS > 0) {
        _focusBoostRemainingS = (_focusBoostRemainingS - dt).clamp(0.0, 1.0).toDouble();
      }
      if (_focusHighlightRemainingS > 0) {
        _focusHighlightRemainingS =
            (_focusHighlightRemainingS - dt).clamp(0.0, 3.0).toDouble();
        if (_focusHighlightRemainingS == 0) {
          _focusedZoneName = null;
        }
      }
      if (_storageFocusPulseS > 0) {
        _storageFocusPulseS = (_storageFocusPulseS - dt).clamp(0.0, 3.0).toDouble();
      }
      if (_selectedHeatmapPulseS > 0) {
        _selectedHeatmapPulseS = (_selectedHeatmapPulseS - dt).clamp(0.0, 3.0).toDouble();
      }

      final inputSmoothing = (dt * (_precisionMode ? 9.4 : 11)).clamp(0.09, 1.0);
      _moveInput = Offset(
        _moveInput.dx + ((_moveInputTarget.dx - _moveInput.dx) * inputSmoothing),
        _moveInput.dy + ((_moveInputTarget.dy - _moveInput.dy) * inputSmoothing),
      );
      _lookInput = Offset(
        _lookInput.dx + ((_lookInputTarget.dx - _lookInput.dx) * inputSmoothing),
        _lookInput.dy + ((_lookInputTarget.dy - _lookInput.dy) * inputSmoothing),
      );
      _liftInput = Offset(
        _liftInput.dx + ((_liftInputTarget.dx - _liftInput.dx) * inputSmoothing),
        _liftInput.dy + ((_liftInputTarget.dy - _liftInput.dy) * inputSmoothing),
      );

      final manualOverride = _moveInputTarget.distance > 0.08 ||
          _lookInputTarget.distance > 0.08 ||
          _liftInputTarget.distance > 0.08;
      if (manualOverride && _autoTourRunning) {
        _stopAutoTour();
      }
      if (_autoTourRunning && _cameraMode == _ViewerCameraMode.firstPerson) {
        _applyAutoTourStep(dt);
      }

      if (_cameraMode == _ViewerCameraMode.firstPerson) {
        final isPersonMode = _traversalMode == _TraversalMode.person;
        final precisionFactor = _precisionMode ? 0.62 : 1.0;
        final gestureTuning = _gestureDriveActive ? 1.0 : 0.0;
        final lookSpeed =
            (isPersonMode ? 2.02 : 2.28) * _sensitivity.lookFactor * precisionFactor;
        final speedFactor = _traversalSpeed.factor * _sensitivity.moveFactor;
        final maxHorizontalSpeed = (isPersonMode ? 1.02 : 1.34) *
            _traversalSpeed.factor *
            precisionFactor *
            _lerpDouble(1.0, 0.92, gestureTuning);
        final lookDx = _lookInput.dx.clamp(-0.92, 0.92).toDouble();
        final lookDy = _lookInput.dy.clamp(-0.92, 0.92).toDouble();
        final lookIntensity = math.max(lookDx.abs(), lookDy.abs()).clamp(0.0, 1.0).toDouble();
        final adaptiveLookFactor = _lerpDouble(0.78, 1.0, lookIntensity);
        final yawSpeedTarget = lookDx * lookSpeed * adaptiveLookFactor;
        final pitchSpeedTarget =
            lookDy * lookSpeed * adaptiveLookFactor * (isPersonMode ? 0.86 : 0.92);
        final lookAccelRate =
            (isPersonMode ? 17.0 : 19.0) * _sensitivity.lookFactor * _lerpDouble(1.0, 0.84, gestureTuning);
        final lookDecelRate =
            (isPersonMode ? 14.0 : 15.6) * _sensitivity.lookFactor * _lerpDouble(1.0, 1.08, gestureTuning);
        final lookReverseRate =
            (isPersonMode ? 23.0 : 25.0) * _sensitivity.lookFactor * _lerpDouble(1.0, 0.74, gestureTuning);
        _lookYawVelocity = _updateVelocityAxis(
          current: _lookYawVelocity,
          target: yawSpeedTarget,
          accelRate: lookAccelRate,
          decelRate: lookDecelRate,
          reverseBrakeRate: lookReverseRate,
          dt: dt,
        );
        _lookPitchVelocity = _updateVelocityAxis(
          current: _lookPitchVelocity,
          target: pitchSpeedTarget,
          accelRate: lookAccelRate,
          decelRate: lookDecelRate,
          reverseBrakeRate: lookReverseRate,
          dt: dt,
        );
        _targetYaw = _normalizeAngle(_targetYaw + (_lookYawVelocity * dt));
        final movementLoad =
            ((_forwardVelocity.abs() + _strafeVelocity.abs()) /
                    (maxHorizontalSpeed * 2))
            .clamp(0.0, 1.0)
            .toDouble();
        final basePitchMin = isPersonMode ? -0.50 : -0.58;
        final basePitchMax = isPersonMode ? 0.46 : 0.56;
        final pitchCenter = isPersonMode ? -0.02 : -0.01;
        final pitchRangeScale = _lerpDouble(
          1.0,
          isPersonMode ? 0.82 : 0.90,
          movementLoad,
        );
        final halfRange =
            (((basePitchMax - basePitchMin) * 0.5) * pitchRangeScale).toDouble();
        final pitchMin = pitchCenter - halfRange;
        final pitchMax = pitchCenter + halfRange;
        _targetPitch = _applySoftPitchLimit(
          _targetPitch - (_lookPitchVelocity * dt),
          min: pitchMin,
          max: pitchMax,
          softZone: 0.085,
        );

        final inputForward = (-_moveInput.dy).clamp(-1.0, 1.0).toDouble();
        final inputStrafe = _moveInput.dx.clamp(-1.0, 1.0).toDouble();
        final strafeBias = isPersonMode ? 0.88 : 0.96;
        final targetForwardVelocity = inputForward * maxHorizontalSpeed;
        final targetStrafeVelocity = inputStrafe * maxHorizontalSpeed * strafeBias;
        final horizontalAccelRate =
            (isPersonMode ? 7.6 : 8.6) *
                speedFactor *
                precisionFactor *
                _lerpDouble(1.0, 0.84, gestureTuning);
        final horizontalDecelRate =
            (isPersonMode ? 6.3 : 7.0) *
                speedFactor *
                precisionFactor *
                _lerpDouble(1.0, 1.12, gestureTuning);
        final horizontalReverseRate =
            (isPersonMode ? 10.2 : 11.4) *
                speedFactor *
                precisionFactor *
                _lerpDouble(1.0, 0.76, gestureTuning);

        _forwardVelocity = _updateVelocityAxis(
          current: _forwardVelocity,
          target: targetForwardVelocity,
          accelRate: horizontalAccelRate,
          decelRate: horizontalDecelRate,
          reverseBrakeRate: horizontalReverseRate,
          dt: dt,
        );
        _strafeVelocity = _updateVelocityAxis(
          current: _strafeVelocity,
          target: targetStrafeVelocity,
          accelRate: horizontalAccelRate,
          decelRate: horizontalDecelRate,
          reverseBrakeRate: horizontalReverseRate,
          dt: dt,
        );
        _forwardVelocity = _forwardVelocity
            .clamp(-maxHorizontalSpeed, maxHorizontalSpeed)
            .toDouble();
        _strafeVelocity = _strafeVelocity
            .clamp(-maxHorizontalSpeed, maxHorizontalSpeed)
            .toDouble();
        if (_forwardVelocity.abs() < 0.0012) {
          _forwardVelocity = 0;
        }
        if (_strafeVelocity.abs() < 0.0012) {
          _strafeVelocity = 0;
        }

        final yawSin = math.sin(_targetYaw);
        final yawCos = math.cos(_targetYaw);
        final worldDeltaStrafe = (_forwardVelocity * yawSin) + (_strafeVelocity * yawCos);
        final worldDeltaForward = (_forwardVelocity * yawCos) - (_strafeVelocity * yawSin);
        var nextForward = (_targetForward + (worldDeltaForward * dt)).clamp(-0.52, 2.8).toDouble();
        var nextStrafe = (_targetStrafe + (worldDeltaStrafe * dt)).clamp(-1.8, 1.8).toDouble();

        if (isPersonMode) {
          final geometry = _navigationGeometry();
          final previousWorld = _cameraToWorld(
            cameraForward: _targetForward,
            cameraStrafe: _targetStrafe,
            geometry: geometry,
          );
          final desiredWorld = _cameraToWorld(
            cameraForward: nextForward,
            cameraStrafe: nextStrafe,
            geometry: geometry,
          );
          final resolvedWorld = _resolvePersonCollision(
            previousWorld: previousWorld,
            desiredWorld: desiredWorld,
            geometry: geometry,
          );
          final resolvedCamera = _worldToCamera(
            world: resolvedWorld,
            geometry: geometry,
          );
          nextForward = resolvedCamera.forward;
          nextStrafe = resolvedCamera.strafe;
        }
        _targetForward = nextForward;
        _targetStrafe = nextStrafe;

        if (isPersonMode) {
          _liftVelocity = 0;
          final speedBlend =
              (_forwardVelocity.abs() + _strafeVelocity.abs()).clamp(0.0, 1.0);
          final walkBob = math.sin(elapsed.inMilliseconds / 120) * 0.008 * speedBlend;
          _targetLift = _approach(_targetLift, 0.12 + walkBob, 6.8, dt);
        } else {
          final maxLiftSpeed = 1.05 * _traversalSpeed.factor * precisionFactor;
          final targetLiftVelocity =
              (-_liftInput.dy).clamp(-1.0, 1.0).toDouble() * maxLiftSpeed;
          final liftAccelRate = 7.1 * speedFactor * precisionFactor;
          final liftDecelRate = 6.2 * speedFactor * precisionFactor;
          final liftReverseRate = 9.8 * speedFactor * precisionFactor;
          _liftVelocity = _updateVelocityAxis(
            current: _liftVelocity,
            target: targetLiftVelocity,
            accelRate: liftAccelRate,
            decelRate: liftDecelRate,
            reverseBrakeRate: liftReverseRate,
            dt: dt,
          );
          _liftVelocity = _liftVelocity.clamp(-maxLiftSpeed, maxLiftSpeed).toDouble();
          if (_liftVelocity.abs() < 0.0012) {
            _liftVelocity = 0;
          }
          _targetLift = (_targetLift + (_liftVelocity * dt)).clamp(-0.56, 1.72).toDouble();
        }
      } else {
        _forwardVelocity *= math.pow(0.14, dt).toDouble();
        _strafeVelocity *= math.pow(0.14, dt).toDouble();
        _liftVelocity *= math.pow(0.14, dt).toDouble();
        _lookYawVelocity = _approach(_lookYawVelocity, 0, 13.8, dt);
        _lookPitchVelocity = _approach(_lookPitchVelocity, 0, 13.8, dt);
        if (_forwardVelocity.abs() < 0.0012) {
          _forwardVelocity = 0;
        }
        if (_strafeVelocity.abs() < 0.0012) {
          _strafeVelocity = 0;
        }
        if (_liftVelocity.abs() < 0.0012) {
          _liftVelocity = 0;
        }
        if (_lookYawVelocity.abs() < 0.0012) {
          _lookYawVelocity = 0;
        }
        if (_lookPitchVelocity.abs() < 0.0012) {
          _lookPitchVelocity = 0;
        }
      }

      final focusSmoothBoost = _focusBoostRemainingS > 0 ? 1.72 : 1.0;
      final gestureSmoothBoost =
          _cameraMode == _ViewerCameraMode.firstPerson && _gestureDriveActive ? 1.18 : 1.0;
      final smoothRate =
          _sensitivity.cameraSmoothRate *
              (_precisionMode ? 1.28 : 1.0) *
              focusSmoothBoost *
              gestureSmoothBoost;
      _manualYaw = _approachAngle(_manualYaw, _targetYaw, smoothRate, dt);
      _manualPitch = _approach(_manualPitch, _targetPitch, smoothRate, dt);
      _cameraForward =
          _approach(_cameraForward, _targetForward, smoothRate * 0.92, dt);
      _cameraStrafe =
          _approach(_cameraStrafe, _targetStrafe, smoothRate * 0.92, dt);
      _cameraLift = _approach(_cameraLift, _targetLift, smoothRate * 0.9, dt);
      _isCameraInMotion = _autoTourRunning ||
          _moveInputTarget.distance > 0.03 ||
          _lookInputTarget.distance > 0.03 ||
          _liftInputTarget.distance > 0.03 ||
          _moveInput.distance > 0.03 ||
          _lookInput.distance > 0.03 ||
          _liftInput.distance > 0.03 ||
          _forwardVelocity.abs() > 0.005 ||
          _strafeVelocity.abs() > 0.005 ||
          _liftVelocity.abs() > 0.005 ||
          _lookYawVelocity.abs() > 0.005 ||
          _lookPitchVelocity.abs() > 0.005;
      if (_cameraMode == _ViewerCameraMode.firstPerson) {
        _sampleRouteTrail(elapsed);
      }
    });
  }

  void _stopAutoTour({bool clearWaypoints = true}) {
    _autoTourRunning = false;
    _autoTourUsesCustomWaypoints = false;
    _autoTourWaypointIndex = 0;
    _autoTourStallTicks = 0;
    if (clearWaypoints) {
      _autoTourWaypoints = <Offset>[];
    }
  }

  List<Offset> _buildAutoTourWaypoints(_NavigationGeometry geometry) {
    final centerX = geometry.length * 0.5;
    final startY = (geometry.width * 0.9).clamp(0.0, geometry.width).toDouble();
    final topY = (geometry.originY + (geometry.stepY * 0.7))
        .clamp(0.0, geometry.width)
        .toDouble();
    final bottomY = (geometry.originY + geometry.rackAreaWidth - (geometry.stepY * 0.7))
        .clamp(0.0, geometry.width)
        .toDouble();

    final rawColumns = <int>[
      1,
      (geometry.columns * 0.24).round(),
      (geometry.columns * 0.42).round(),
      (geometry.columns * 0.58).round(),
      (geometry.columns * 0.76).round(),
      geometry.columns - 2,
    ];
    final uniqueColumns = <int>{
      for (final value in rawColumns) value.clamp(1, geometry.columns - 2).toInt(),
    }.toList(growable: false)
      ..sort();

    final waypoints = <Offset>[Offset(centerX, startY)];
    var towardsTop = true;
    for (final column in uniqueColumns) {
      final aisleX = (geometry.originX + (column * geometry.stepX))
          .clamp(0.0, geometry.length)
          .toDouble();
      waypoints.add(Offset(aisleX, towardsTop ? topY : bottomY));
      towardsTop = !towardsTop;
    }
    waypoints.add(Offset(centerX, startY));
    return waypoints;
  }

  void _toggleAutoTour() {
    final geometry = _navigationGeometry();
    setState(() {
      if (_autoTourRunning) {
        _stopAutoTour();
        return;
      }
      _startAutoTourWithWaypoints(
        geometry: geometry,
        waypoints: _buildAutoTourWaypoints(geometry),
        usesCustomWaypoints: false,
      );
    });
  }

  void _startAutoTourWithWaypoints({
    required _NavigationGeometry geometry,
    required List<Offset> waypoints,
    required bool usesCustomWaypoints,
  }) {
    if (waypoints.isEmpty) {
      _stopAutoTour();
      return;
    }
    final normalizedWaypoints = _normalizeTourWaypoints(
      waypoints: waypoints,
      geometry: geometry,
    );
    if (normalizedWaypoints.isEmpty) {
      _stopAutoTour();
      return;
    }
    final preparedWaypoints = usesCustomWaypoints
        ? normalizedWaypoints
        : _buildTraversalPathFromWaypoints(
            waypoints: normalizedWaypoints,
            geometry: geometry,
          );
    if (preparedWaypoints.isEmpty) {
      _stopAutoTour();
      return;
    }

    _cameraMode = _ViewerCameraMode.firstPerson;
    _traversalMode = _TraversalMode.person;
    _autoTourUsesCustomWaypoints = usesCustomWaypoints;
    _autoTourWaypoints = List<Offset>.from(preparedWaypoints, growable: true);
    _autoTourWaypointIndex = 0;
    _autoTourStallTicks = 0;
    _autoTourRunning = true;

    final currentWorld = _cameraToWorld(
      cameraForward: _cameraForward,
      cameraStrafe: _cameraStrafe,
      geometry: geometry,
    );
    _routeTrail
      ..clear()
      ..add(currentWorld);

    _targetLift = 0.12;
    _forwardVelocity = 0;
    _strafeVelocity = 0;
    _liftVelocity = 0;
    _lookYawVelocity = 0;
    _lookPitchVelocity = 0;
    _moveInput = Offset.zero;
    _lookInput = Offset.zero;
    _liftInput = Offset.zero;
    _moveInputTarget = Offset.zero;
    _lookInputTarget = Offset.zero;
    _liftInputTarget = Offset.zero;
  }

  List<Offset> _normalizeTourWaypoints({
    required List<Offset> waypoints,
    required _NavigationGeometry geometry,
  }) {
    final normalized = <Offset>[];
    for (final point in waypoints) {
      final clamped = Offset(
        point.dx.clamp(0.0, geometry.length).toDouble(),
        point.dy.clamp(0.0, geometry.width).toDouble(),
      );
      if (normalized.isNotEmpty && (normalized.last - clamped).distance <= 0.16) {
        continue;
      }
      normalized.add(clamped);
    }
    return normalized;
  }

  List<Offset> _buildTraversalPathFromWaypoints({
    required List<Offset> waypoints,
    required _NavigationGeometry geometry,
  }) {
    if (waypoints.length < 2) {
      return waypoints;
    }
    final densified = <Offset>[waypoints.first];
    const maxSegmentLength = 0.88;
    for (var i = 0; i < waypoints.length - 1; i++) {
      final start = waypoints[i];
      final end = waypoints[i + 1];
      final delta = end - start;
      final distance = delta.distance;
      if (distance <= 0.0001) {
        continue;
      }
      final direction = delta / distance;
      final steps = math.max(1, (distance / maxSegmentLength).ceil());
      for (var step = 1; step <= steps; step++) {
        final t = (step / steps).clamp(0.0, 1.0).toDouble();
        final point = Offset(
          start.dx + (direction.dx * distance * t),
          start.dy + (direction.dy * distance * t),
        );
        if ((densified.last - point).distance > 0.12) {
          densified.add(point);
        }
      }
    }

    if (densified.length < 3) {
      return densified;
    }

    final smoothed = <Offset>[densified.first];
    for (var i = 1; i < densified.length - 1; i++) {
      final previous = densified[i - 1];
      final current = densified[i];
      final next = densified[i + 1];
      final inVec = current - previous;
      final outVec = next - current;
      final inLen = inVec.distance;
      final outLen = outVec.distance;
      if (inLen <= 0.0001 || outLen <= 0.0001) {
        if ((smoothed.last - current).distance > 0.10) {
          smoothed.add(current);
        }
        continue;
      }

      final inDir = inVec / inLen;
      final outDir = outVec / outLen;
      final dot = ((inDir.dx * outDir.dx) + (inDir.dy * outDir.dy))
          .clamp(-1.0, 1.0)
          .toDouble();
      final turnStrength = ((1 - dot) * 0.5).clamp(0.0, 1.0).toDouble();
      if (turnStrength < 0.08) {
        if ((smoothed.last - current).distance > 0.10) {
          smoothed.add(current);
        }
        continue;
      }

      final radius = (math.min(inLen, outLen) * 0.34).clamp(0.18, 0.74).toDouble();
      final entry = current - (inDir * radius);
      final exit = current + (outDir * radius);
      if ((smoothed.last - entry).distance > 0.10) {
        smoothed.add(entry);
      }
      final interpolationSteps = (3 + (turnStrength * 3).round()).clamp(3, 6);
      for (var step = 1; step < interpolationSteps; step++) {
        final t = (step / interpolationSteps).clamp(0.0, 1.0).toDouble();
        final oneMinusT = 1 - t;
        final point = Offset(
          (oneMinusT * oneMinusT * entry.dx) +
              (2 * oneMinusT * t * current.dx) +
              (t * t * exit.dx),
          (oneMinusT * oneMinusT * entry.dy) +
              (2 * oneMinusT * t * current.dy) +
              (t * t * exit.dy),
        );
        if ((smoothed.last - point).distance > 0.10) {
          smoothed.add(point);
        }
      }
      if ((smoothed.last - exit).distance > 0.10) {
        smoothed.add(exit);
      }
    }
    if ((smoothed.last - densified.last).distance > 0.10) {
      smoothed.add(densified.last);
    }

    return smoothed
        .map(
          (point) => Offset(
            point.dx.clamp(0.0, geometry.length).toDouble(),
            point.dy.clamp(0.0, geometry.width).toDouble(),
          ),
        )
        .toList(growable: false);
  }

  void _applyAutoTourStep(double dt) {
    if (!_autoTourRunning ||
        _autoTourWaypoints.isEmpty ||
        _cameraMode != _ViewerCameraMode.firstPerson) {
      return;
    }
    final geometry = _navigationGeometry();
    final currentWorld = _cameraToWorld(
      cameraForward: _targetForward,
      cameraStrafe: _targetStrafe,
      geometry: geometry,
    );

    final safeIndex = _autoTourWaypointIndex.clamp(0, _autoTourWaypoints.length - 1).toInt();
    var targetIndex = safeIndex;
    var waypoint = _autoTourWaypoints[targetIndex];
    var toWaypoint = waypoint - currentWorld;
    var distanceToWaypoint = toWaypoint.distance;
    final lastWaypointIndex = _autoTourWaypoints.length - 1;
    final hasNextWaypoint = targetIndex < lastWaypointIndex;
    final arrivalRadius = hasNextWaypoint ? 0.72 : 0.95;
    if (distanceToWaypoint <= arrivalRadius) {
      if (targetIndex >= lastWaypointIndex) {
        _stopAutoTour();
        return;
      }
      targetIndex += 1;
      _autoTourWaypointIndex = targetIndex;
      waypoint = _autoTourWaypoints[targetIndex];
      toWaypoint = waypoint - currentWorld;
      distanceToWaypoint = toWaypoint.distance;
    }
    if (distanceToWaypoint <= 0.0001) {
      return;
    }

    final hasNext = targetIndex < lastWaypointIndex;
    final nextWaypoint = hasNext ? _autoTourWaypoints[targetIndex + 1] : waypoint;
    final previousWaypoint = targetIndex > 0 ? _autoTourWaypoints[targetIndex - 1] : currentWorld;
    final cornerBlendStart = hasNext ? 3.8 : 1.8;
    final cornerT = (1 - (distanceToWaypoint / cornerBlendStart)).clamp(0.0, 1.0).toDouble();
    final cornerBlend = _sCurve01(cornerT);
    final bendTarget = hasNext
        ? Offset.lerp(waypoint, nextWaypoint, (cornerBlend * 0.64).clamp(0.0, 0.64)) ?? waypoint
        : waypoint;

    final incoming = waypoint - previousWaypoint;
    final outgoing = nextWaypoint - waypoint;
    final incomingDir = incoming.distance <= 0.0001 ? Offset.zero : (incoming / incoming.distance);
    final outgoingDir = outgoing.distance <= 0.0001 ? Offset.zero : (outgoing / outgoing.distance);
    final dot = ((incomingDir.dx * outgoingDir.dx) + (incomingDir.dy * outgoingDir.dy))
        .clamp(-1.0, 1.0)
        .toDouble();
    final turnSharpness = hasNext ? ((1 - dot) * 0.5).clamp(0.0, 1.0).toDouble() : 0.0;

    final toBendTarget = bendTarget - currentWorld;
    final distanceToBend = toBendTarget.distance;
    if (distanceToBend <= 0.0001) {
      return;
    }

    final speedBase = _traversalMode == _TraversalMode.person ? 7.0 : 8.4;
    final speedRaw = speedBase *
        _traversalSpeed.factor *
        _sensitivity.moveFactor *
        (_precisionMode ? 0.8 : 1.0);
    final approachDistance = hasNext ? 3.2 : 2.6;
    final approachT = (distanceToWaypoint / approachDistance).clamp(0.0, 1.0).toDouble();
    final approachFactor = hasNext
        ? _lerpDouble(0.42, 1.0, _sCurve01(approachT))
        : _lerpDouble(0.24, 0.82, _sCurve01(approachT));
    final turnDamping = _lerpDouble(1.0, 0.78, turnSharpness * cornerBlend);
    final speed = speedRaw * approachFactor * turnDamping;
    final step = math.min(distanceToBend, speed * dt);
    final direction = Offset(
      toBendTarget.dx / distanceToBend,
      toBendTarget.dy / distanceToBend,
    );
    final desiredWorld = currentWorld + Offset(direction.dx * step, direction.dy * step);
    final resolvedWorld = _traversalMode == _TraversalMode.person
        ? _resolvePersonCollision(
            previousWorld: currentWorld,
            desiredWorld: desiredWorld,
            geometry: geometry,
          )
        : desiredWorld;
    final progressDistance = (resolvedWorld - currentWorld).distance;
    if (_traversalMode == _TraversalMode.person) {
      final stallThreshold = math.max(0.02, step * 0.18);
      final stillFarFromTarget = distanceToWaypoint > 1.05;
      final stalled = step > 0.08 && stillFarFromTarget && progressDistance < stallThreshold;
      if (stalled) {
        _autoTourStallTicks += 1;
      } else if (_autoTourStallTicks > 0) {
        _autoTourStallTicks = 0;
      }

      if (_autoTourStallTicks >= 9) {
        final inserted = _insertAutoTourDetour(
          currentWorld: currentWorld,
          waypoint: waypoint,
          targetIndex: targetIndex,
          geometry: geometry,
        );
        if (inserted) {
          _autoTourStallTicks = 0;
          return;
        }
      }

      if (_autoTourStallTicks >= 20) {
        if (targetIndex < lastWaypointIndex) {
          _autoTourWaypointIndex = targetIndex + 1;
          _autoTourStallTicks = 0;
          return;
        }
        _stopAutoTour();
        return;
      }
    } else if (_autoTourStallTicks != 0) {
      _autoTourStallTicks = 0;
    }

    final cameraPosition = _worldToCamera(
      world: resolvedWorld,
      geometry: geometry,
    );
    _targetForward = cameraPosition.forward;
    _targetStrafe = cameraPosition.strafe;

    if (_traversalMode == _TraversalMode.person) {
      _targetLift = _approach(_targetLift, 0.12, 8.0, dt);
      _liftVelocity = 0;
    }

    final lookAhead = hasNext
        ? Offset.lerp(waypoint, nextWaypoint, (0.38 + (cornerBlend * 0.34)).clamp(0.0, 0.86)) ??
            waypoint
        : waypoint;
    final facing = lookAhead - resolvedWorld;
    if (facing.distance > 0.03) {
      _targetYaw = _normalizeAngle(math.atan2(facing.dx, facing.dy));
    }
    final desiredPitch = _traversalMode == _TraversalMode.fly
        ? _lerpDouble(-0.07, -0.11, turnSharpness * cornerBlend)
        : _lerpDouble(-0.02, -0.045, turnSharpness * cornerBlend);
    _targetPitch = _approach(
      _targetPitch,
      desiredPitch,
      5.0,
      dt,
    );
    _forwardVelocity = 0;
    _strafeVelocity = 0;
    _lookYawVelocity = 0;
    _lookPitchVelocity = 0;

    if (_routeTrail.isEmpty || (_routeTrail.last - resolvedWorld).distance >= 0.3) {
      _routeTrail.add(resolvedWorld);
      if (_routeTrail.length > 420) {
        _routeTrail.removeRange(0, _routeTrail.length - 420);
      }
    }
  }

  Offset _clampWorldPoint(
    Offset point,
    _NavigationGeometry geometry, {
    double margin = 0,
  }) {
    final safeMargin = margin.clamp(0, math.min(geometry.length, geometry.width) * 0.48);
    final minX = safeMargin.toDouble();
    final minY = safeMargin.toDouble();
    final maxX = math.max(minX, geometry.length - safeMargin);
    final maxY = math.max(minY, geometry.width - safeMargin);
    return Offset(
      point.dx.clamp(minX, maxX).toDouble(),
      point.dy.clamp(minY, maxY).toDouble(),
    );
  }

  double _autoTourOperatorRadius(_NavigationGeometry geometry) {
    final wallMargin = math.max(1.2, math.min(geometry.stepX, geometry.stepY) * 0.24);
    return wallMargin * 0.74;
  }

  bool _isAutoTourPointWalkable({
    required Offset point,
    required _NavigationGeometry geometry,
    required double operatorRadius,
  }) {
    final clamped = _clampWorldPoint(
      point,
      geometry,
      margin: operatorRadius,
    );
    return !_isBlocked(clamped, geometry, operatorRadius);
  }

  ({List<Offset> points, double score})? _buildAutoTourDetourCandidate({
    required Offset currentWorld,
    required Offset waypoint,
    required _NavigationGeometry geometry,
    required double operatorRadius,
    required double sideSign,
  }) {
    final toTarget = waypoint - currentWorld;
    final distanceToTarget = toTarget.distance;
    if (distanceToTarget <= 0.2) {
      return null;
    }
    final forward = Offset(
      toTarget.dx / distanceToTarget,
      toTarget.dy / distanceToTarget,
    );
    final side = Offset(-forward.dy * sideSign, forward.dx * sideSign);
    final aisleScale = math.max(geometry.stepX, geometry.stepY);
    final sideDistance = math.max(operatorRadius * 2.2, aisleScale * 0.52);
    final forwardDistance = math.max(
      operatorRadius * 2.0,
      math.min(distanceToTarget * 0.68, aisleScale * 1.6),
    );

    final sideTarget = _clampWorldPoint(
      currentWorld + (side * sideDistance),
      geometry,
      margin: operatorRadius,
    );
    final sideResolved = _resolvePersonCollision(
      previousWorld: currentWorld,
      desiredWorld: sideTarget,
      geometry: geometry,
    );
    if ((sideResolved - currentWorld).distance < (sideDistance * 0.42)) {
      return null;
    }
    if (!_isAutoTourPointWalkable(
      point: sideResolved,
      geometry: geometry,
      operatorRadius: operatorRadius,
    )) {
      return null;
    }

    final forwardTarget = _clampWorldPoint(
      sideResolved + (forward * forwardDistance),
      geometry,
      margin: operatorRadius,
    );
    final forwardResolved = _resolvePersonCollision(
      previousWorld: sideResolved,
      desiredWorld: forwardTarget,
      geometry: geometry,
    );
    if ((forwardResolved - sideResolved).distance < (forwardDistance * 0.34)) {
      return null;
    }
    if (!_isAutoTourPointWalkable(
      point: forwardResolved,
      geometry: geometry,
      operatorRadius: operatorRadius,
    )) {
      return null;
    }

    final remaining = (waypoint - forwardResolved).distance;
    final score = remaining + ((sideResolved - currentWorld).distance * 0.14);
    return (points: <Offset>[sideResolved, forwardResolved], score: score);
  }

  bool _insertAutoTourDetour({
    required Offset currentWorld,
    required Offset waypoint,
    required int targetIndex,
    required _NavigationGeometry geometry,
  }) {
    if (targetIndex < 0 || targetIndex >= _autoTourWaypoints.length) {
      return false;
    }
    if (_autoTourWaypoints.length >= 360) {
      return false;
    }
    final operatorRadius = _autoTourOperatorRadius(geometry);
    final leftCandidate = _buildAutoTourDetourCandidate(
      currentWorld: currentWorld,
      waypoint: waypoint,
      geometry: geometry,
      operatorRadius: operatorRadius,
      sideSign: -1,
    );
    final rightCandidate = _buildAutoTourDetourCandidate(
      currentWorld: currentWorld,
      waypoint: waypoint,
      geometry: geometry,
      operatorRadius: operatorRadius,
      sideSign: 1,
    );

    ({List<Offset> points, double score})? best;
    if (leftCandidate != null && rightCandidate != null) {
      best = leftCandidate.score <= rightCandidate.score ? leftCandidate : rightCandidate;
    } else {
      best = leftCandidate ?? rightCandidate;
    }
    if (best == null) {
      return false;
    }

    final deduped = <Offset>[];
    Offset reference = currentWorld;
    for (final point in best.points) {
      if ((point - reference).distance <= 0.18) {
        continue;
      }
      deduped.add(point);
      reference = point;
    }
    if (deduped.isEmpty) {
      return false;
    }

    _autoTourWaypoints.insertAll(targetIndex, deduped);
    _autoTourWaypointIndex = targetIndex;
    return true;
  }

  double _normalizeAngle(double angle) {
    const twoPi = math.pi * 2;
    var normalized = angle % twoPi;
    if (normalized > math.pi) {
      normalized -= twoPi;
    } else if (normalized < -math.pi) {
      normalized += twoPi;
    }
    return normalized;
  }

  double _angleDelta(double from, double to) {
    return _normalizeAngle(to - from);
  }

  Offset _applyRadialDeadZone(
    Offset value, {
    double deadZone = 0.035,
  }) {
    final magnitude = value.distance;
    if (magnitude <= deadZone) {
      return Offset.zero;
    }
    final normalized = ((magnitude - deadZone) / (1 - deadZone))
        .clamp(0.0, 1.0)
        .toDouble();
    final direction = magnitude <= 0.000001 ? Offset.zero : (value / magnitude);
    final curved = _applyInputResponseCurve(normalized);
    final scaled = direction * curved;
    return Offset(
      scaled.dx.clamp(-1.0, 1.0).toDouble(),
      scaled.dy.clamp(-1.0, 1.0).toDouble(),
    );
  }

  double _applyInputResponseCurve(double value) {
    final safe = value.clamp(0.0, 1.0).toDouble();
    return (safe * safe * (3 - (2 * safe))).clamp(0.0, 1.0).toDouble();
  }

  double _lerpDouble(double from, double to, double t) {
    final factor = t.clamp(0.0, 1.0).toDouble();
    return from + ((to - from) * factor);
  }

  double _sCurve01(double t) {
    final x = t.clamp(0.0, 1.0).toDouble();
    return x * x * (3 - (2 * x));
  }

  double _applySoftPitchLimit(
    double value, {
    required double min,
    required double max,
    double softZone = 0.08,
  }) {
    if (min >= max) {
      return value.clamp(min, max).toDouble();
    }
    final clamped = value.clamp(min, max).toDouble();
    if (softZone <= 0) {
      return clamped;
    }
    final lowerEdge = min + softZone;
    final upperEdge = max - softZone;
    if (clamped < lowerEdge) {
      final t = ((clamped - min) / softZone).clamp(0.0, 1.0).toDouble();
      final eased = t * t * (3 - (2 * t));
      return min + (softZone * eased);
    }
    if (clamped > upperEdge) {
      final t = ((max - clamped) / softZone).clamp(0.0, 1.0).toDouble();
      final eased = t * t * (3 - (2 * t));
      return max - (softZone * eased);
    }
    return clamped;
  }

  Offset _blendOffset(
    Offset current,
    Offset next,
    double blend,
  ) {
    final factor = blend.clamp(0.0, 1.0).toDouble();
    return Offset(
      current.dx + ((next.dx - current.dx) * factor),
      current.dy + ((next.dy - current.dy) * factor),
    );
  }

  double _normalizeSignedAxis(
    double value, {
    required double divisor,
    double deadZone = 0.04,
    double curve = 1.45,
  }) {
    if (divisor <= 0.0001) {
      return 0;
    }
    final normalized = (value / divisor).clamp(-1.0, 1.0).toDouble();
    final absValue = normalized.abs();
    if (absValue <= deadZone) {
      return 0;
    }
    final mapped = ((absValue - deadZone) / (1 - deadZone)).clamp(0.0, 1.0).toDouble();
    final curved = math.pow(mapped, curve).toDouble();
    final signed = normalized.isNegative ? -curved : curved;
    return signed.clamp(-1.0, 1.0).toDouble();
  }

  void _setMoveInputTarget(
    Offset value, {
    double deadZone = 0.038,
    double blend = 0.34,
  }) {
    final sanitized = _applyRadialDeadZone(value, deadZone: deadZone);
    _moveInputTarget = _blendOffset(_moveInputTarget, sanitized, blend);
  }

  void _setLookInputTarget(
    Offset value, {
    double deadZone = 0.038,
    double blend = 0.34,
  }) {
    final sanitized = _applyRadialDeadZone(value, deadZone: deadZone);
    _lookInputTarget = _blendOffset(_lookInputTarget, sanitized, blend);
  }

  void _setLiftInputTarget(
    Offset value, {
    double deadZone = 0.038,
    double blend = 0.34,
  }) {
    final sanitized = _applyRadialDeadZone(value, deadZone: deadZone);
    _liftInputTarget = _blendOffset(_liftInputTarget, sanitized, blend);
  }

  double _approach(double current, double target, double rate, double dt) {
    if ((target - current).abs() < 0.00001) {
      return target;
    }
    final factor = 1 - math.exp(-rate * dt);
    return current + ((target - current) * factor);
  }

  double _updateVelocityAxis({
    required double current,
    required double target,
    required double accelRate,
    required double decelRate,
    required double reverseBrakeRate,
    required double dt,
  }) {
    final currentAbs = current.abs();
    final targetAbs = target.abs();
    final sameDirection = current == 0 || target == 0 || current.sign == target.sign;
    final rate = sameDirection
        ? (targetAbs >= currentAbs ? accelRate : decelRate)
        : reverseBrakeRate;
    final next = _approach(current, target, rate, dt);
    if (next.abs() < 0.0008 && targetAbs < 0.0008) {
      return 0;
    }
    return next;
  }

  double _approachAngle(double current, double target, double rate, double dt) {
    final delta = _angleDelta(current, target);
    if (delta.abs() < 0.00001) {
      return _normalizeAngle(target);
    }
    final factor = 1 - math.exp(-rate * dt);
    return _normalizeAngle(current + (delta * factor));
  }

  void _resetCamera() {
    setState(() {
      _stopAutoTour();
      _manualYaw = 0;
      _manualPitch = 0;
      _cameraForward = 0;
      _cameraStrafe = 0;
      _cameraLift = 0;
      _targetYaw = 0;
      _targetPitch = 0;
      _targetForward = 0;
      _targetStrafe = 0;
      _targetLift = 0;
      _forwardVelocity = 0;
      _strafeVelocity = 0;
      _liftVelocity = 0;
      _lookYawVelocity = 0;
      _lookPitchVelocity = 0;
      _moveInput = Offset.zero;
      _lookInput = Offset.zero;
      _liftInput = Offset.zero;
      _moveInputTarget = Offset.zero;
      _lookInputTarget = Offset.zero;
      _liftInputTarget = Offset.zero;
      _lastScale = 1;
      _smoothedScaleDelta = 1;
      _lastGesturePointerCount = 0;
      _gestureModeBlend = 0;
      _smoothedPinchForward = 0;
      _smoothedTwoFingerMove = Offset.zero;
    });
  }

  void _sampleRouteTrail(Duration elapsed) {
    const minSampleGap = Duration(milliseconds: 95);
    if (elapsed - _lastTrailSample < minSampleGap) {
      return;
    }
    _lastTrailSample = elapsed;
    final geometry = _navigationGeometry();
    final point = _cameraToWorld(
      cameraForward: _cameraForward,
      cameraStrafe: _cameraStrafe,
      geometry: geometry,
    );
    final minDistance = math.max(0.30, math.min(geometry.stepX, geometry.stepY) * 0.2);
    if (_routeTrail.isEmpty || (_routeTrail.last - point).distance >= minDistance) {
      _routeTrail.add(point);
      const maxPoints = 360;
      if (_routeTrail.length > maxPoints) {
        _routeTrail.removeRange(0, _routeTrail.length - maxPoints);
      }
    }
  }

  double _routeDistanceMeters() {
    if (_routeTrail.length < 2) {
      return 0;
    }
    var distance = 0.0;
    for (var i = 1; i < _routeTrail.length; i++) {
      distance += (_routeTrail[i] - _routeTrail[i - 1]).distance;
    }
    return distance;
  }

  void _clearRouteTrail() {
    setState(() {
      _routeTrail.clear();
    });
  }

  void _focusNextInspectionMarker(
    BuildContext context,
    List<_InspectionMarker> markers,
  ) {
    if (markers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Marker für Fokus vorhanden')),
      );
      return;
    }

    final currentIndex = _focusedMarkerId == null
        ? -1
        : markers.indexWhere((marker) => marker.id == _focusedMarkerId);
    final nextIndex = (currentIndex + 1) % markers.length;
    final marker = markers[nextIndex];

    final geometry = _navigationGeometry();
    final currentWorld = _cameraToWorld(
      cameraForward: _cameraForward,
      cameraStrafe: _cameraStrafe,
      geometry: geometry,
    );
    final targetWorld = _cameraToWorld(
      cameraForward: marker.forward,
      cameraStrafe: marker.strafe,
      geometry: geometry,
    );
    final delta = targetWorld - currentWorld;
    final yaw = delta.distance > 0.001 ? math.atan2(delta.dx, delta.dy) : _targetYaw;

    setState(() {
      _focusedMarkerId = marker.id;
      _targetForward = marker.forward.clamp(-0.52, 2.8).toDouble();
      _targetStrafe = marker.strafe.clamp(-1.8, 1.8).toDouble();
      _targetLift = _cameraMode == _ViewerCameraMode.firstPerson &&
              _traversalMode == _TraversalMode.person
          ? 0.12
          : marker.lift;
      _targetYaw = _normalizeAngle(yaw);
      _targetPitch = (_targetPitch * 0.6).clamp(-0.52, 0.52);
    });
  }

  double _worldXFromCamera() {
    final geometry = _navigationGeometry();
    final world = _cameraToWorld(
      cameraForward: _cameraForward,
      cameraStrafe: _cameraStrafe,
      geometry: geometry,
    );
    return world.dx;
  }

  double _worldYFromCamera() {
    final geometry = _navigationGeometry();
    final world = _cameraToWorld(
      cameraForward: _cameraForward,
      cameraStrafe: _cameraStrafe,
      geometry: geometry,
    );
    return world.dy;
  }

  String _headingLabel() {
    final raw = (_manualYaw * 180 / math.pi) % 360;
    final normalized = raw < 0 ? raw + 360 : raw;
    return '${normalized.round()} deg';
  }

  void _applyPreset(_CameraPreset preset) {
    final geometry = _navigationGeometry();
    setState(() {
      _stopAutoTour();
      switch (preset) {
        case _CameraPreset.overall:
          _targetYaw = 0;
          _targetPitch = -0.10;
          _targetStrafe = 0;
          _targetForward = -0.06;
          _targetLift = _cameraMode == _ViewerCameraMode.firstPerson ? 0.12 : 0.16;
        case _CameraPreset.dock:
          final cameraPos = _worldToCamera(
            world: Offset(geometry.length * 0.5, geometry.width * 0.92),
            geometry: geometry,
          );
          _targetYaw = math.pi;
          _targetPitch = -0.03;
          _targetStrafe = cameraPos.strafe;
          _targetForward = cameraPos.forward;
          _targetLift = _cameraMode == _ViewerCameraMode.firstPerson ? 0.12 : 0.1;
        case _CameraPreset.aisle:
          final cameraPos = _worldToCamera(
            world: Offset(
              geometry.originX + (geometry.rackAreaLength * 0.5),
              geometry.originY + (geometry.stepY * 0.45),
            ),
            geometry: geometry,
          );
          _targetYaw = 0;
          _targetPitch = -0.02;
          _targetStrafe = cameraPos.strafe;
          _targetForward = cameraPos.forward;
          _targetLift = _cameraMode == _ViewerCameraMode.firstPerson ? 0.12 : 0.12;
      }
      _forwardVelocity = 0;
      _strafeVelocity = 0;
      _liftVelocity = 0;
      _lookYawVelocity = 0;
      _lookPitchVelocity = 0;
      _moveInput = Offset.zero;
      _lookInput = Offset.zero;
      _liftInput = Offset.zero;
      _moveInputTarget = Offset.zero;
      _lookInputTarget = Offset.zero;
      _liftInputTarget = Offset.zero;
      _lastScale = 1;
      _smoothedScaleDelta = 1;
      _smoothedGestureFocalDelta = Offset.zero;
      _lastGesturePointerCount = 0;
      _gestureModeBlend = 0;
      _smoothedPinchForward = 0;
      _smoothedTwoFingerMove = Offset.zero;
    });
  }

  void _focusZoneByName(String zoneName) {
    final normalized = zoneName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }
    final zones = widget.model?.zones;
    if (zones == null || zones.isEmpty) {
      return;
    }

    WarehouseModelZone? target;
    for (final zone in zones) {
      if (zone.name.trim().toLowerCase() == normalized) {
        target = zone;
        break;
      }
    }
    target ??= () {
      for (final zone in zones) {
        final name = zone.name.trim().toLowerCase();
        if (name.contains(normalized) || normalized.contains(name)) {
          return zone;
        }
      }
      return null;
    }();
    if (target == null) {
      return;
    }

    final geometry = _navigationGeometry();
    final centerX = ((target.x + (target.width * 0.5)).clamp(0.02, 0.98) * geometry.length)
        .toDouble();
    final centerY = ((target.y + (target.height * 0.5)).clamp(0.02, 0.98) * geometry.width)
        .toDouble();
    final focusWorld = Offset(centerX, centerY);
    final currentWorld = _cameraToWorld(
      cameraForward: _targetForward,
      cameraStrafe: _targetStrafe,
      geometry: geometry,
    );
    final delta = focusWorld - currentWorld;
    final focusCamera = _worldToCamera(
      world: focusWorld,
      geometry: geometry,
    );

    setState(() {
      _stopAutoTour();
      _focusedZoneName = target!.name;
      _focusBoostRemainingS = 0.68;
      _focusHighlightRemainingS = 2.2;
      _targetForward = focusCamera.forward;
      _targetStrafe = focusCamera.strafe;
      _targetLift = _cameraMode == _ViewerCameraMode.firstPerson &&
              _traversalMode == _TraversalMode.person
          ? 0.12
          : 0.12;
      if (delta.distance > 0.08) {
        _targetYaw = _normalizeAngle(math.atan2(delta.dx, delta.dy));
      }
      _targetPitch = _cameraMode == _ViewerCameraMode.firstPerson ? -0.02 : -0.1;
      _forwardVelocity = 0;
      _strafeVelocity = 0;
      _liftVelocity = 0;
      _lookYawVelocity = 0;
      _lookPitchVelocity = 0;
      _moveInputTarget = Offset.zero;
      _lookInputTarget = Offset.zero;
      _liftInputTarget = Offset.zero;
      _moveInput = Offset.zero;
      _lookInput = Offset.zero;
      _liftInput = Offset.zero;
    });
  }

  void _addInspectionMarker() {
    final now = DateTime.now();
    final marker = _InspectionMarker(
      id: now.microsecondsSinceEpoch.toString(),
      type: _selectedMarkerType,
      status: _selectedMarkerStatus,
      priority: _selectedMarkerPriority,
      owner: _selectedMarkerOwner,
      reference: _selectedMarkerReference.trim(),
      forward: _cameraForward,
      strafe: _cameraStrafe,
      lift: _cameraLift,
      createdAt: now,
      dueDate: now.add(Duration(days: _selectedDueInDays)),
    );
    setState(() {
      _inspectionMarkers = <_InspectionMarker>[..._inspectionMarkers, marker];
      _focusedMarkerId = marker.id;
    });
  }

  void _undoInspectionMarker() {
    if (_inspectionMarkers.isEmpty) {
      return;
    }
    setState(() {
      _inspectionMarkers = _inspectionMarkers.sublist(0, _inspectionMarkers.length - 1);
      _focusedMarkerId = _inspectionMarkers.isEmpty ? null : _inspectionMarkers.last.id;
    });
  }

  void _clearInspectionMarkers() {
    if (_inspectionMarkers.isEmpty) {
      return;
    }
    setState(() {
      _inspectionMarkers = <_InspectionMarker>[];
      _focusedMarkerId = null;
    });
  }

  List<_InspectionMarker> _visibleInspectionMarkers() {
    return _inspectionMarkers;
  }

  void _updateInspectionMarker(
    String id, {
    _InspectionStatus? status,
    _InspectionPriority? priority,
    String? owner,
    String? reference,
    DateTime? dueDate,
    bool setDueDate = false,
  }) {
    setState(() {
      _inspectionMarkers = _inspectionMarkers
          .map(
            (marker) => marker.id == id
                ? marker.copyWith(
                    status: status,
                    priority: priority,
                    owner: owner,
                    reference: reference,
                    dueDate: dueDate,
                    setDueDate: setDueDate,
                  )
                : marker,
          )
          .toList(growable: false);
    });
  }

  Future<void> _editMarkerOwner(BuildContext context, _InspectionMarker marker) async {
    final controller = TextEditingController(text: marker.owner);
    final newOwner = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Verantwortlich'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name / Team',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newOwner == null || newOwner.isEmpty) {
      return;
    }
    _updateInspectionMarker(marker.id, owner: newOwner);
  }

  Future<void> _editMarkerReference(BuildContext context, _InspectionMarker marker) async {
    final controller = TextEditingController(text: marker.reference);
    final newReference = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Referenz'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Foto-ID / Ticket / Notiz',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newReference == null) {
      return;
    }
    _updateInspectionMarker(marker.id, reference: newReference);
  }

  Future<void> _editMarkerDueDate(BuildContext context, _InspectionMarker marker) async {
    final initialDate = marker.dueDate ?? DateTime.now().add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: initialDate,
      helpText: 'Deadline wählen',
    );
    if (picked == null) {
      return;
    }
    _updateInspectionMarker(marker.id, dueDate: picked, setDueDate: true);
  }

  Future<void> _openMarkerManager(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final markers = _inspectionMarkers.reversed.toList(growable: false);
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.74,
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.xs,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Marker Review (${_inspectionMarkers.length})',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_inspectionMarkers.isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _inspectionMarkers = <_InspectionMarker>[];
                                  _focusedMarkerId = null;
                                });
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.delete_sweep_outlined),
                              label: const Text('Alle löschen'),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: markers.isEmpty
                          ? const Center(child: Text('Noch keine Marker vorhanden'))
                          : ListView.separated(
                              itemCount: markers.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final marker = markers[index];
                                return Padding(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: marker.type.color(),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.xs),
                                          Expanded(
                                            child: Text(
                                              '${marker.type.label}  -  ${marker.createdAt.toLocal()}'
                                              '${_isOverdue(marker) ? '  -  Überfällig' : ''}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context).textTheme.labelLarge,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Wrap(
                                        spacing: AppSpacing.xs,
                                        runSpacing: AppSpacing.xs,
                                        children: <Widget>[
                                          PopupMenuButton<_InspectionStatus>(
                                            initialValue: marker.status,
                                            onSelected: (value) {
                                              _updateInspectionMarker(marker.id, status: value);
                                              setSheetState(() {});
                                            },
                                            itemBuilder: (context) => _InspectionStatus.values
                                                .map(
                                                  (value) =>
                                                      CheckedPopupMenuItem<_InspectionStatus>(
                                                    value: value,
                                                    checked: marker.status == value,
                                                    child: Text(value.label),
                                                  ),
                                                )
                                                .toList(growable: false),
                                            child: _ReviewChip(
                                              label: marker.status.label,
                                            ),
                                          ),
                                          PopupMenuButton<_InspectionPriority>(
                                            initialValue: marker.priority,
                                            onSelected: (value) {
                                              _updateInspectionMarker(marker.id, priority: value);
                                              setSheetState(() {});
                                            },
                                            itemBuilder: (context) => _InspectionPriority.values
                                                .map(
                                                  (value) => CheckedPopupMenuItem<
                                                      _InspectionPriority>(
                                                    value: value,
                                                    checked: marker.priority == value,
                                                    child: Text(value.label),
                                                  ),
                                                )
                                                .toList(growable: false),
                                            child: _ReviewChip(
                                              label: marker.priority.label,
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              await _editMarkerOwner(context, marker);
                                              if (!context.mounted) {
                                                return;
                                              }
                                              setSheetState(() {});
                                            },
                                            child: Text('Owner: ${marker.owner}'),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              await _editMarkerReference(context, marker);
                                              if (!context.mounted) {
                                                return;
                                              }
                                              setSheetState(() {});
                                            },
                                            child: Text(
                                              marker.reference.isEmpty
                                                  ? 'Ref: -'
                                                  : 'Ref: ${marker.reference}',
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              await _editMarkerDueDate(context, marker);
                                              if (!context.mounted) {
                                                return;
                                              }
                                              setSheetState(() {});
                                            },
                                            child: Text(
                                              marker.dueDate == null
                                                  ? 'Deadline: -'
                                                  : 'Deadline: ${marker.dueDate!.toLocal().toString().split(' ').first}',
                                            ),
                                          ),
                                          if (marker.dueDate != null)
                                            TextButton(
                                              onPressed: () {
                                                _updateInspectionMarker(
                                                  marker.id,
                                                  dueDate: null,
                                                  setDueDate: true,
                                                );
                                                setSheetState(() {});
                                              },
                                              child: const Text('Deadline löschen'),
                                            ),
                                          TextButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                _inspectionMarkers = _inspectionMarkers
                                                    .where((m) => m.id != marker.id)
                                                    .toList(growable: false);
                                                if (_focusedMarkerId == marker.id) {
                                                  _focusedMarkerId = _inspectionMarkers.isEmpty
                                                      ? null
                                                      : _inspectionMarkers.first.id;
                                                }
                                              });
                                              setSheetState(() {});
                                            },
                                            icon: const Icon(Icons.delete_outline),
                                            label: const Text('Entfernen'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Map<String, int> _markerSummary([Iterable<_InspectionMarker>? source]) {
    final markerSource = source ?? _inspectionMarkers;
    var bottleneck = 0;
    var safety = 0;
    var damage = 0;
    for (final marker in markerSource) {
      if (marker.type == _InspectionMarkerType.bottleneck) {
        bottleneck++;
      } else if (marker.type == _InspectionMarkerType.safety) {
        safety++;
      } else {
        damage++;
      }
    }
    return <String, int>{
      'engpass': bottleneck,
      'sicherheit': safety,
      'schaden': damage,
    };
  }

  bool _isOverdue(_InspectionMarker marker) {
    if (marker.dueDate == null || marker.status == _InspectionStatus.closed) {
      return false;
    }
    return marker.dueDate!.isBefore(DateTime.now());
  }

  int _overdueCount([Iterable<_InspectionMarker>? source]) {
    final markers = source ?? _inspectionMarkers;
    var count = 0;
    for (final marker in markers) {
      if (_isOverdue(marker)) {
        count++;
      }
    }
    return count;
  }

  int _markerRisk(_InspectionMarker marker) {
    final typeWeight = switch (marker.type) {
      _InspectionMarkerType.bottleneck => 2,
      _InspectionMarkerType.safety => 3,
      _InspectionMarkerType.damage => 4,
    };
    final statusFactor = switch (marker.status) {
      _InspectionStatus.open => 1.0,
      _InspectionStatus.inReview => 0.65,
      _InspectionStatus.closed => 0.25,
    };
    var risk = (typeWeight * marker.priority.weight * statusFactor).round();
    if (_isOverdue(marker)) {
      risk += 2;
    }
    return risk;
  }

  int _riskScore([Iterable<_InspectionMarker>? source]) {
    final markers = source ?? _inspectionMarkers;
    var score = 0;
    for (final marker in markers) {
      score += _markerRisk(marker);
    }
    return score;
  }

  String _buildInspectionExportJson() {
    final geometry = _navigationGeometry();
    final summary = _markerSummary();
    final payload = <String, Object>{
      'warehouse': <String, Object>{
        'id': widget.warehouse.id,
        'name': widget.warehouse.name,
        'location': widget.warehouse.location,
      },
      'exportedAt': DateTime.now().toIso8601String(),
      'markerCount': _inspectionMarkers.length,
      'summary': summary,
      'markers': _inspectionMarkers
          .map(
            (marker) {
              final world = _cameraToWorld(
                cameraForward: marker.forward,
                cameraStrafe: marker.strafe,
                geometry: geometry,
              );
              return <String, Object?>{
                'id': marker.id,
                'type': marker.type.label,
                'status': marker.status.label,
                'priority': marker.priority.label,
                'owner': marker.owner,
                'reference': marker.reference,
                'createdAt': marker.createdAt.toIso8601String(),
                'dueDate': marker.dueDate?.toIso8601String(),
                'overdue': _isOverdue(marker),
                'risk': _markerRisk(marker),
                'camera': <String, double>{
                  'forward': marker.forward,
                  'strafe': marker.strafe,
                  'lift': marker.lift,
                },
                'world': <String, double>{
                  'x': world.dx,
                  'y': world.dy,
                },
              };
            },
          )
          .toList(growable: false),
    };
    return JsonEncoder.withIndent('  ').convert(payload);
  }

  String _escapeCsvCell(String input) {
    final escaped = input.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _buildInspectionExportCsv() {
    final geometry = _navigationGeometry();
    final summary = _markerSummary();
    final buffer = StringBuffer();
    buffer.writeln('exported_at,warehouse_id,warehouse_name,warehouse_location,marker_count,risk_score');
    buffer.writeln(
      '${_escapeCsvCell(DateTime.now().toIso8601String())},'
      '${_escapeCsvCell(widget.warehouse.id)},'
      '${_escapeCsvCell(widget.warehouse.name)},'
      '${_escapeCsvCell(widget.warehouse.location)},'
      '${_inspectionMarkers.length},'
      '${_riskScore()}',
    );
    buffer.writeln();
    buffer.writeln('summary_engpass,summary_sicherheit,summary_schaden');
    buffer.writeln(
      '${summary['engpass']},${summary['sicherheit']},${summary['schaden']}',
    );
    buffer.writeln('summary_overdue');
    buffer.writeln('${_overdueCount()}');
    buffer.writeln();
    buffer.writeln(
      'id,type,status,priority,owner,reference,due_date,overdue,risk,created_at,camera_forward,camera_strafe,camera_lift,world_x_m,world_y_m',
    );
    for (final marker in _inspectionMarkers) {
      final world = _cameraToWorld(
        cameraForward: marker.forward,
        cameraStrafe: marker.strafe,
        geometry: geometry,
      );
      buffer.writeln(
        '${_escapeCsvCell(marker.id)},'
        '${_escapeCsvCell(marker.type.label)},'
        '${_escapeCsvCell(marker.status.label)},'
        '${_escapeCsvCell(marker.priority.label)},'
        '${_escapeCsvCell(marker.owner)},'
        '${_escapeCsvCell(marker.reference)},'
        '${_escapeCsvCell(marker.dueDate?.toIso8601String() ?? '')},'
        '${_isOverdue(marker)},'
        '${_markerRisk(marker)},'
        '${_escapeCsvCell(marker.createdAt.toIso8601String())},'
        '${marker.forward.toStringAsFixed(4)},'
        '${marker.strafe.toStringAsFixed(4)},'
        '${marker.lift.toStringAsFixed(4)},'
        '${world.dx.toStringAsFixed(3)},'
        '${world.dy.toStringAsFixed(3)}',
      );
    }
    return buffer.toString();
  }

  Future<void> _exportInspectionMarkers(BuildContext context) async {
    final jsonText = _buildInspectionExportJson();
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Marker Export (JSON)'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(
                jsonText,
                style: GoogleFonts.dmMono(
                  textStyle: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Schliessen'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: jsonText));
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('JSON in Zwischenablage kopiert')),
                );
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Kopieren'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportInspectionMarkersCsv(BuildContext context) async {
    final csvText = _buildInspectionExportCsv();
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Marker Export (Tabellenformat)'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(
                csvText,
                style: GoogleFonts.dmMono(
                  textStyle: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Schliessen'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: csvText));
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Daten in Zwischenablage kopiert')),
                );
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Kopieren'),
            ),
          ],
        );
      },
    );
  }

  _NavigationGeometry _navigationGeometry() {
    final layout = widget.warehouse.layoutSpec;
    final baseRows = (widget.model?.shelfRows ?? layout?.rackRowCount ?? 8).clamp(2, 18);
    final baseColumns = (widget.model?.shelfColumns ?? 10).clamp(3, 26);
    final aisle = _aisleSpread;
    final length = ((widget.model?.warehouseLengthM ?? layout?.lengthM ?? 70) * 1.72 * aisle).toDouble();
    final width = ((widget.model?.warehouseWidthM ?? layout?.widthM ?? 42) * 1.58 * aisle).toDouble();
    final cacheKey = Object.hash(length, width, baseRows, baseColumns, aisle);
    final cached = _cachedNavigationGeometry;
    if (cached != null && _cachedNavigationGeometryKey == cacheKey) {
      return cached;
    }
    final rows = (baseRows * 1.26).round().clamp(4, 20);
    final columns = (baseColumns * 1.28).round().clamp(6, 28);

    final rackAreaLength = length * 0.86;
    final rackAreaWidth = width * 0.76;
    final originX = (length - rackAreaLength) * 0.5;
    final originY = (width - rackAreaWidth) * 0.5;
    final stepX = rackAreaLength / columns;
    final stepY = rackAreaWidth / rows;

    final geometry = _NavigationGeometry(
      length: length,
      width: width,
      rows: rows,
      columns: columns,
      originX: originX,
      originY: originY,
      rackAreaLength: rackAreaLength,
      rackAreaWidth: rackAreaWidth,
      stepX: stepX,
      stepY: stepY,
      // Regalgroesse bleibt absolut konstant (durch /aisle kompensiert) -> nur
      // die Gaenge zwischen den Reihen/Spalten werden breiter.
      rackLength: (stepX / aisle) * 0.66,
      rackDepth: (stepY / aisle) * 0.34,
    );
    _cachedNavigationGeometry = geometry;
    _cachedNavigationGeometryKey = cacheKey;
    return geometry;
  }

  _RenderQuality _renderQualityHint() {
    if (_isCameraInMotion) {
      return _RenderQuality.performance;
    }
    if (_cameraMode == _ViewerCameraMode.firstPerson && widget.heatmapVisible) {
      return _RenderQuality.performance;
    }
    if (widget.heatmapVisible && _cameraMode == _ViewerCameraMode.orbit) {
      return kIsWeb ? _RenderQuality.performance : _RenderQuality.balanced;
    }
    if (_cameraMode == _ViewerCameraMode.firstPerson) {
      return kIsWeb ? _RenderQuality.performance : _RenderQuality.balanced;
    }
    return _RenderQuality.auto;
  }

  Offset _cameraToWorld({
    required double cameraForward,
    required double cameraStrafe,
    required _NavigationGeometry geometry,
  }) {
    return Offset(
      ((geometry.length * 0.5) + (cameraStrafe * geometry.length * 0.36))
          .clamp(0.0, geometry.length)
          .toDouble(),
      ((geometry.width * 0.5) + (cameraForward * geometry.width * 0.56))
          .clamp(0.0, geometry.width)
          .toDouble(),
    );
  }

  _CameraPlanePosition _worldToCamera({
    required Offset world,
    required _NavigationGeometry geometry,
  }) {
    final strafe =
        ((world.dx - (geometry.length * 0.5)) / (geometry.length * 0.36)).clamp(-1.8, 1.8);
    final forward =
        ((world.dy - (geometry.width * 0.5)) / (geometry.width * 0.56)).clamp(-0.52, 2.8);
    return _CameraPlanePosition(
      forward: forward.toDouble(),
      strafe: strafe.toDouble(),
    );
  }

  Offset _resolvePersonCollision({
    required Offset previousWorld,
    required Offset desiredWorld,
    required _NavigationGeometry geometry,
  }) {
    final wallMargin = math.max(1.2, math.min(geometry.stepX, geometry.stepY) * 0.24);
    final operatorRadius = wallMargin * 0.74;

    Offset clampToBounds(Offset point) {
      return Offset(
        point.dx.clamp(wallMargin, geometry.length - wallMargin).toDouble(),
        point.dy.clamp(wallMargin, geometry.width - wallMargin).toDouble(),
      );
    }

    var current = clampToBounds(previousWorld);
    final start = current;
    final desired = clampToBounds(desiredWorld);
    if (!_isBlocked(desired, geometry, operatorRadius)) {
      return desired;
    }

    final delta = desired - current;
    if (delta.distance <= 0.0001) {
      return current;
    }

    final stepSize = math.max(operatorRadius * 0.28, 0.12);
    final steps = (delta.distance / stepSize).ceil().clamp(1, 30).toInt();
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final next = clampToBounds(start + (delta * t));
      if (!_isBlocked(next, geometry, operatorRadius)) {
        current = next;
        continue;
      }

      final horizontalFirst = delta.dx.abs() >= delta.dy.abs();
      final primarySlide = horizontalFirst
          ? clampToBounds(Offset(next.dx, current.dy))
          : clampToBounds(Offset(current.dx, next.dy));
      if (!_isBlocked(primarySlide, geometry, operatorRadius)) {
        current = primarySlide;
        continue;
      }

      final secondarySlide = horizontalFirst
          ? clampToBounds(Offset(current.dx, next.dy))
          : clampToBounds(Offset(next.dx, current.dy));
      if (!_isBlocked(secondarySlide, geometry, operatorRadius)) {
        current = secondarySlide;
        continue;
      }

      final nudge = math.max(operatorRadius * 0.42, 0.12);
      final nudgeCandidates = horizontalFirst
          ? <Offset>[
              clampToBounds(Offset(current.dx, next.dy + nudge)),
              clampToBounds(Offset(current.dx, next.dy - nudge)),
            ]
          : <Offset>[
              clampToBounds(Offset(next.dx + nudge, current.dy)),
              clampToBounds(Offset(next.dx - nudge, current.dy)),
            ];
      var appliedNudge = false;
      for (final candidate in nudgeCandidates) {
        if (_isBlocked(candidate, geometry, operatorRadius)) {
          continue;
        }
        current = candidate;
        appliedNudge = true;
        break;
      }
      if (appliedNudge) {
        continue;
      }

      break;
    }
    return current;
  }

  void _moveToWorldPosition({
    required Offset worldPosition,
    required _NavigationGeometry geometry,
    bool appendRoute = false,
  }) {
    final clampedWorld = Offset(
      worldPosition.dx.clamp(0.0, geometry.length).toDouble(),
      worldPosition.dy.clamp(0.0, geometry.width).toDouble(),
    );
    final previousWorld = _cameraToWorld(
      cameraForward: _targetForward,
      cameraStrafe: _targetStrafe,
      geometry: geometry,
    );
    final resolvedWorld = _cameraMode == _ViewerCameraMode.firstPerson &&
            _traversalMode == _TraversalMode.person
        ? _resolvePersonCollision(
            previousWorld: previousWorld,
            desiredWorld: clampedWorld,
            geometry: geometry,
          )
        : clampedWorld;
    final cameraPosition = _worldToCamera(
      world: resolvedWorld,
      geometry: geometry,
    );
    final delta = resolvedWorld - previousWorld;
    setState(() {
      _targetForward = cameraPosition.forward;
      _targetStrafe = cameraPosition.strafe;
      if (_cameraMode == _ViewerCameraMode.firstPerson &&
          _traversalMode == _TraversalMode.person) {
        _targetLift = 0.12;
      }
      if (delta.distance > 0.24) {
        _targetYaw = _normalizeAngle(math.atan2(delta.dx, delta.dy));
      }
      _forwardVelocity = 0;
      _strafeVelocity = 0;
      _liftVelocity = 0;
      _lookYawVelocity = 0;
      _lookPitchVelocity = 0;
      _moveInputTarget = Offset.zero;
      _lookInputTarget = Offset.zero;
      _liftInputTarget = Offset.zero;
      _moveInput = Offset.zero;
      _lookInput = Offset.zero;
      _liftInput = Offset.zero;
      if (appendRoute &&
          (_routeTrail.isEmpty || (_routeTrail.last - resolvedWorld).distance > 0.3)) {
        _routeTrail.add(resolvedWorld);
        if (_routeTrail.length > 360) {
          _routeTrail.removeRange(0, _routeTrail.length - 360);
        }
      }
    });
  }

  void _moveViaMiniMap({
    required Offset localPosition,
    required Size miniMapSize,
    required _NavigationGeometry geometry,
    bool appendRoute = false,
  }) {
    if (_autoTourRunning) {
      setState(() {
        _stopAutoTour();
      });
    }
    final worldPosition = _miniMapLocalToWorld(
      localPosition: localPosition,
      miniMapSize: miniMapSize,
      geometry: geometry,
    );
    _moveToWorldPosition(
      worldPosition: worldPosition,
      geometry: geometry,
      appendRoute: appendRoute,
    );
  }

  Offset _miniMapLocalToWorld({
    required Offset localPosition,
    required Size miniMapSize,
    required _NavigationGeometry geometry,
  }) {
    final safeWidth = miniMapSize.width <= 1 ? 1.0 : miniMapSize.width;
    final safeHeight = miniMapSize.height <= 1 ? 1.0 : miniMapSize.height;
    final normalizedX = (localPosition.dx / safeWidth).clamp(0.0, 1.0).toDouble();
    final normalizedY = (localPosition.dy / safeHeight).clamp(0.0, 1.0).toDouble();
    return Offset(
      normalizedX * geometry.length,
      normalizedY * geometry.width,
    );
  }

  _Warehouse3DBase _buildViewerBaseForHitTest(_NavigationGeometry geometry) {
    final layout = widget.warehouse.layoutSpec;
    const megaLengthFactor = 1.72;
    const megaWidthFactor = 1.58;
    const megaHeightFactor = 1.22;
    final length =
        (widget.model?.warehouseLengthM ?? layout?.lengthM ?? 70) * megaLengthFactor;
    final width =
        (widget.model?.warehouseWidthM ?? layout?.widthM ?? 42) * megaWidthFactor;
    final height =
        (widget.model?.warehouseHeightM ?? layout?.heightM ?? 14) * megaHeightFactor;
    return _Warehouse3DBase(
      length: length,
      width: width,
      height: height,
      rows: geometry.rows,
      columns: geometry.columns,
      levels: _availableShelfLevels.clamp(2, 10).toInt(),
      zones: widget.model?.zones ?? const <WarehouseModelZone>[],
    );
  }

  _Projection _buildProjectionForHitTest({
    required _Warehouse3DBase base,
    required Size viewportSize,
  }) {
    return _Projection(
      base: base,
      size: viewportSize,
      cameraDrift: 0,
      cameraYaw: _manualYaw,
      cameraPitch: _manualPitch,
      cameraForward: _cameraForward,
      cameraStrafe: _cameraStrafe,
      cameraLift: _cameraLift,
      isFirstPersonPov: _cameraMode == _ViewerCameraMode.firstPerson,
    );
  }

  _HeatmapRackSelection? _resolveHeatmapRackSelectionFromCanvas({
    required Offset localPosition,
    required Size viewportSize,
    required _NavigationGeometry geometry,
    required int levelFilter,
  }) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return null;
    }
    final dataLength = widget.heatmapData.length;
    final base = _buildViewerBaseForHitTest(geometry);
    final projection = _buildProjectionForHitTest(
      base: base,
      viewportSize: viewportSize,
    );
    final rackHeight = (base.height * 0.74).clamp(9.0, 22.0);
    final sampleZ = rackHeight * 0.34;

    _HeatmapRackSelection? nearest;
    var nearestDistance = double.infinity;
    final threshold =
        (math.min(viewportSize.width, viewportSize.height) * 0.07).clamp(24.0, 44.0).toDouble();

    for (var row = 0; row < geometry.rows; row++) {
      final rackY =
          geometry.originY + row * geometry.stepY + ((geometry.stepY - geometry.rackDepth) * 0.5);
      for (var column = 0; column < geometry.columns; column++) {
        final rackX = geometry.originX +
            column * geometry.stepX +
            ((geometry.stepX - geometry.rackLength) * 0.5);
        final center = Offset(
          rackX + (geometry.rackLength * 0.5),
          rackY + (geometry.rackDepth * 0.5),
        );
        final projected = projection.project(center.dx, center.dy, sampleZ);
        if (projected.dx < -40 ||
            projected.dy < -40 ||
            projected.dx > viewportSize.width + 40 ||
            projected.dy > viewportSize.height + 40) {
          continue;
        }

        final rawIndex = (row * geometry.columns) + column;
        final rackIndex = rawIndex % (dataLength <= 0 ? 1 : dataLength);
        final entry = dataLength <= 0 ? null : widget.heatmapData[rackIndex];
        final baseHeat = entry?.valueFor(widget.heatmapMetric) ?? 0.2;
        final heatValue = _adjustHeatmapForLevel(
          heatValue: baseHeat,
          rackIndex: rackIndex,
          levelFilter: levelFilter,
          totalLevels: _availableShelfLevels,
        );
        final selection = _HeatmapRackSelection(
          row: row,
          column: column,
          rackIndex: rawIndex,
          zoneId: entry?.zoneId,
          zoneName: entry?.zoneName ?? 'Rack ${row + 1}/${column + 1}',
          heatValue: heatValue,
          worldCenter: center,
        );
        final distance = (projected - localPosition).distance;
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = selection;
        }
      }
    }

    if (nearest != null && nearestDistance <= threshold) {
      return nearest;
    }
    return null;
  }

  _HeatmapRackSelection? _resolveHeatmapRackSelectionFromWorld({
    required Offset worldPosition,
    required _NavigationGeometry geometry,
    required int levelFilter,
  }) {
    final dataLength = widget.heatmapData.length;
    if (geometry.rows <= 0 || geometry.columns <= 0) {
      return null;
    }

    _HeatmapRackSelection? nearest;
    var nearestDistance = double.infinity;
    final hitPadding = math.max(0.12, math.min(geometry.rackLength, geometry.rackDepth) * 0.14);
    final snapDistance = math.max(geometry.stepX, geometry.stepY) * 0.62;

    for (var row = 0; row < geometry.rows; row++) {
      final rackY =
          geometry.originY + row * geometry.stepY + ((geometry.stepY - geometry.rackDepth) * 0.5);
      for (var column = 0; column < geometry.columns; column++) {
        final rackX = geometry.originX +
            column * geometry.stepX +
            ((geometry.stepX - geometry.rackLength) * 0.5);
        final rackRect = Rect.fromLTWH(
          rackX,
          rackY,
          geometry.rackLength,
          geometry.rackDepth,
        );
        final center = Offset(
          rackX + (geometry.rackLength * 0.5),
          rackY + (geometry.rackDepth * 0.5),
        );
        final rawIndex = (row * geometry.columns) + column;
        final rackIndex = rawIndex % (dataLength <= 0 ? 1 : dataLength);
        final entry = dataLength <= 0 ? null : widget.heatmapData[rackIndex];
        final baseHeat = entry?.valueFor(widget.heatmapMetric) ?? 0.2;
        final heatValue = _adjustHeatmapForLevel(
          heatValue: baseHeat,
          rackIndex: rackIndex,
          levelFilter: levelFilter,
          totalLevels: _availableShelfLevels,
        );
        final selection = _HeatmapRackSelection(
          row: row,
          column: column,
          rackIndex: rawIndex,
          zoneId: entry?.zoneId,
          zoneName: entry?.zoneName ?? 'Rack ${row + 1}/${column + 1}',
          heatValue: heatValue,
          worldCenter: center,
        );

        if (rackRect.inflate(hitPadding).contains(worldPosition)) {
          return selection;
        }

        final distance = (center - worldPosition).distance;
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = selection;
        }
      }
    }

    if (nearest != null && nearestDistance <= snapDistance) {
      return nearest;
    }
    return null;
  }

  double _adjustHeatmapForLevel({
    required double heatValue,
    required int rackIndex,
    required int levelFilter,
    required int totalLevels,
  }) {
    if (levelFilter < 0 || totalLevels <= 1) {
      return heatValue.clamp(0, 1).toDouble();
    }
    final safeLevel = levelFilter.clamp(0, totalLevels - 1);
    final normalizedLevel = safeLevel / (totalLevels - 1);
    final levelBias = (1.06 - (normalizedLevel * 0.18)).clamp(0.78, 1.08);
    final rackVariation = (((rackIndex + (safeLevel * 3)) % 9) / 8)
        .clamp(0.0, 1.0)
        .toDouble();
    final variationFactor = 0.88 + (rackVariation * 0.22);
    return (heatValue * levelBias * variationFactor).clamp(0, 1).toDouble();
  }

  String _heatmapMetricLabel(ViewerHeatmapMetric metric) {
    return switch (metric) {
      ViewerHeatmapMetric.utilization => 'Auslastung',
      ViewerHeatmapMetric.pickRate => 'Pickrate',
      ViewerHeatmapMetric.congestion => 'Stau',
      ViewerHeatmapMetric.abcA => 'ABC-A',
    };
  }

  String _heatmapSeverityLabel(double value) {
    final safe = value.clamp(0, 1).toDouble();
    if (safe >= 0.85) {
      return 'Kritisch';
    }
    if (safe >= 0.65) {
      return 'Hoch';
    }
    if (safe >= 0.45) {
      return 'Mittel';
    }
    return 'Niedrig';
  }

  Color _heatmapSeverityColor(double value) {
    final safe = value.clamp(0, 1).toDouble();
    if (safe >= 0.85) {
      return Colors.red.shade700;
    }
    if (safe >= 0.65) {
      return Colors.orange.shade700;
    }
    if (safe >= 0.45) {
      return Colors.amber.shade700;
    }
    return Colors.green.shade700;
  }

  _HeatmapRackSelection? _selectHeatmapRackFromMiniMap({
    required BuildContext context,
    required Offset localPosition,
    required Size miniMapSize,
    required _NavigationGeometry geometry,
    required int levelFilter,
    bool showFeedback = true,
  }) {
    final worldPosition = _miniMapLocalToWorld(
      localPosition: localPosition,
      miniMapSize: miniMapSize,
      geometry: geometry,
    );
    final selection = _resolveHeatmapRackSelectionFromWorld(
      worldPosition: worldPosition,
      geometry: geometry,
      levelFilter: levelFilter,
    );

    setState(() {
      _selectedHeatmapSelection = selection;
      _selectedHeatmapPulseS = selection == null ? 0 : 2.4;
    });

    if (selection != null) {
      _trackRecentHeatmapSelection(selection);
    }

    if (selection?.zoneId != null && (widget.model?.zones.isNotEmpty ?? false)) {
      _focusZoneByName(selection!.zoneName);
    }

    if (showFeedback) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        messenger.hideCurrentSnackBar();
        final text = selection == null
            ? 'Kein Heatmap-Hotspot erkannt'
            : '${selection.zoneName} - ${_heatmapMetricLabel(widget.heatmapMetric)} ${((selection.heatValue * 100).round())}% (${_heatmapSeverityLabel(selection.heatValue)})';
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1700),
            content: Text(text),
            action: selection == null
                ? null
                : SnackBarAction(
                    label: 'Ansehen',
                    onPressed: () {
                      _moveToWorldPosition(
                        worldPosition: selection.worldCenter,
                        geometry: geometry,
                        appendRoute: true,
                      );
                    },
                  ),
          ),
        );
      }
    }
    return selection;
  }

  _HeatmapRackSelection? _selectHeatmapRackFromCanvas({
    required BuildContext context,
    required Offset localPosition,
    required Size viewportSize,
    required _NavigationGeometry geometry,
    required int levelFilter,
    bool showFeedback = true,
  }) {
    final selection = _resolveHeatmapRackSelectionFromCanvas(
      localPosition: localPosition,
      viewportSize: viewportSize,
      geometry: geometry,
      levelFilter: levelFilter,
    );
    setState(() {
      _selectedHeatmapSelection = selection;
      _selectedHeatmapPulseS = selection == null ? 0 : 2.4;
    });
    if (selection != null) {
      _trackRecentHeatmapSelection(selection);
    }
    if (selection?.zoneId != null && (widget.model?.zones.isNotEmpty ?? false)) {
      _focusZoneByName(selection!.zoneName);
    }

    if (showFeedback) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        messenger.hideCurrentSnackBar();
        final text = selection == null
            ? 'Kein Rack-Hotspot im 3D-Bild gefunden'
            : '${selection.zoneName} - ${_heatmapMetricLabel(widget.heatmapMetric)} ${((selection.heatValue * 100).round())}% (${_heatmapSeverityLabel(selection.heatValue)})';
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1700),
            content: Text(text),
            action: selection == null
                ? null
                : SnackBarAction(
                    label: 'Ansehen',
                    onPressed: () {
                      _moveToWorldPosition(
                        worldPosition: selection.worldCenter,
                        geometry: geometry,
                        appendRoute: true,
                      );
                    },
                  ),
          ),
        );
      }
    }
    return selection;
  }

  void _clearSelectedHeatmapRack() {
    if (_selectedHeatmapSelection == null && _selectedHeatmapPulseS <= 0) {
      return;
    }
    setState(() {
      _selectedHeatmapSelection = null;
      _selectedHeatmapPulseS = 0;
    });
  }

  void _trackRecentHeatmapSelection(_HeatmapRackSelection selection) {
    final existingIndex = _recentHeatmapSelections.indexWhere(
      (item) => item.rackIndex == selection.rackIndex,
    );
    if (existingIndex == 0) {
      return;
    }
    setState(() {
      if (existingIndex > 0) {
        _recentHeatmapSelections.removeAt(existingIndex);
      }
      _recentHeatmapSelections.insert(0, selection);
      if (_recentHeatmapSelections.length > 6) {
        _recentHeatmapSelections.removeRange(
          6,
          _recentHeatmapSelections.length,
        );
      }
    });
  }

  void _clearRecentHeatmapSelections() {
    if (_recentHeatmapSelections.isEmpty) {
      return;
    }
    setState(() {
      _recentHeatmapSelections.clear();
    });
  }

  List<_HeatmapRackSelection> _topHeatmapHotspots({
    required _NavigationGeometry geometry,
    required int levelFilter,
    required _HeatmapHotspotFilter hotspotFilter,
    int limit = 5,
  }) {
    if (geometry.rows <= 0 || geometry.columns <= 0 || widget.heatmapData.isEmpty) {
      return const <_HeatmapRackSelection>[];
    }
    final hotspots = <_HeatmapRackSelection>[];
    final maxCount = limit.clamp(1, 12);
    for (var row = 0; row < geometry.rows; row++) {
      final rackY =
          geometry.originY + row * geometry.stepY + ((geometry.stepY - geometry.rackDepth) * 0.5);
      for (var column = 0; column < geometry.columns; column++) {
        final rackX = geometry.originX +
            column * geometry.stepX +
            ((geometry.stepX - geometry.rackLength) * 0.5);
        final center = Offset(
          rackX + (geometry.rackLength * 0.5),
          rackY + (geometry.rackDepth * 0.5),
        );
        final rawIndex = (row * geometry.columns) + column;
        final rackIndex = rawIndex % widget.heatmapData.length;
        final entry = widget.heatmapData[rackIndex];
        final baseHeat = entry.valueFor(widget.heatmapMetric);
        final heatValue = _adjustHeatmapForLevel(
          heatValue: baseHeat,
          rackIndex: rackIndex,
          levelFilter: levelFilter,
          totalLevels: _availableShelfLevels,
        );
        if (!_matchesHotspotFilter(heatValue, hotspotFilter)) {
          continue;
        }
        hotspots.add(
          _HeatmapRackSelection(
            row: row,
            column: column,
            rackIndex: rawIndex,
            zoneId: entry.zoneId,
            zoneName: entry.zoneName,
            heatValue: heatValue,
            worldCenter: center,
          ),
        );
      }
    }
    hotspots.sort((a, b) => b.heatValue.compareTo(a.heatValue));
    return hotspots.take(maxCount).toList(growable: false);
  }

  bool _matchesHotspotFilter(
    double heatValue,
    _HeatmapHotspotFilter hotspotFilter,
  ) {
    final safe = heatValue.clamp(0, 1).toDouble();
    return switch (hotspotFilter) {
      _HeatmapHotspotFilter.critical => safe >= 0.85,
      _HeatmapHotspotFilter.high => safe >= 0.65,
      _HeatmapHotspotFilter.all => true,
    };
  }

  String _hotspotFilterLabel(_HeatmapHotspotFilter filter) {
    return switch (filter) {
      _HeatmapHotspotFilter.critical => 'Kritisch',
      _HeatmapHotspotFilter.high => 'Hoch+',
      _HeatmapHotspotFilter.all => 'Alle',
    };
  }

  void _focusNextHeatmapHotspot(
    BuildContext context,
    _NavigationGeometry geometry,
  ) {
    if (!widget.heatmapVisible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Heatmap bitte zuerst einschalten')),
      );
      return;
    }
    final hotspots = _topHeatmapHotspots(
      geometry: geometry,
      levelFilter: -1,
      hotspotFilter: _heatmapHotspotFilter,
      limit: 6,
    );
    if (hotspots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Keine Heatmap-Hotspots für Filter ${_hotspotFilterLabel(_heatmapHotspotFilter)}',
          ),
        ),
      );
      return;
    }
    final currentRackIndex = _selectedHeatmapSelection?.rackIndex;
    final currentIndex = currentRackIndex == null
        ? -1
        : hotspots.indexWhere((entry) => entry.rackIndex == currentRackIndex);
    final nextIndex = (currentIndex + 1) % hotspots.length;
    final selection = hotspots[nextIndex];
    _focusHeatmapHotspotSelection(
      context: context,
      geometry: geometry,
      selection: selection,
      rank: nextIndex + 1,
      total: hotspots.length,
    );
  }

  void _focusHeatmapHotspotSelection({
    required BuildContext context,
    required _NavigationGeometry geometry,
    required _HeatmapRackSelection selection,
    int? rank,
    int? total,
  }) {
    setState(() {
      _selectedHeatmapSelection = selection;
      _selectedHeatmapPulseS = 2.4;
    });
    _trackRecentHeatmapSelection(selection);
    if (selection.zoneId != null && (widget.model?.zones.isNotEmpty ?? false)) {
      _focusZoneByName(selection.zoneName);
    }
    _moveToWorldPosition(
      worldPosition: selection.worldCenter,
      geometry: geometry,
      appendRoute: true,
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      final rankText = rank != null && total != null ? 'Hotspot $rank/$total: ' : '';
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1700),
          content: Text(
            '$rankText${selection.zoneName} - '
            '${_heatmapMetricLabel(widget.heatmapMetric)} '
            '${(selection.heatValue * 100).round()}%',
          ),
        ),
      );
    }
  }

  void _addCustomWaypoint(Offset worldPosition, _NavigationGeometry geometry) {
    final normalized = Offset(
      worldPosition.dx.clamp(0.0, geometry.length).toDouble(),
      worldPosition.dy.clamp(0.0, geometry.width).toDouble(),
    );
    setState(() {
      if (_customTourWaypoints.isNotEmpty &&
          (_customTourWaypoints.last - normalized).distance <= 0.35) {
        return;
      }
      _customTourWaypoints.add(normalized);
    });
  }

  void _addCustomWaypointAtCurrentPosition() {
    final geometry = _navigationGeometry();
    final currentWorld = _cameraToWorld(
      cameraForward: _cameraForward,
      cameraStrafe: _cameraStrafe,
      geometry: geometry,
    );
    _addCustomWaypoint(currentWorld, geometry);
  }

  void _removeLastCustomWaypoint() {
    if (_customTourWaypoints.isEmpty) {
      return;
    }
    setState(() {
      _customTourWaypoints.removeLast();
    });
  }

  void _clearCustomWaypoints() {
    if (_customTourWaypoints.isEmpty) {
      return;
    }
    setState(() {
      _customTourWaypoints.clear();
      if (_autoTourRunning && _autoTourUsesCustomWaypoints) {
        _stopAutoTour();
      }
    });
  }

  void _toggleCustomAutoTour(BuildContext context) {
    final geometry = _navigationGeometry();
    if (_autoTourRunning && _autoTourUsesCustomWaypoints) {
      setState(() {
        _stopAutoTour();
      });
      return;
    }
    if (_customTourWaypoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mindestens 2 Wegpunkte für Custom-Rundgang erforderlich'),
        ),
      );
      return;
    }
    setState(() {
      final currentWorld = _cameraToWorld(
        cameraForward: _cameraForward,
        cameraStrafe: _cameraStrafe,
        geometry: geometry,
      );
      final waypoints = <Offset>[currentWorld, ..._customTourWaypoints];
      _startAutoTourWithWaypoints(
        geometry: geometry,
        waypoints: waypoints,
        usesCustomWaypoints: true,
      );
    });
  }

  Future<void> _openWarehouseOverviewMap(BuildContext context) async {
    final geometry = _navigationGeometry();
    final transformationController = TransformationController();
    var levelFilter = -1;
    var showHeatmapOverlay = widget.heatmapVisible;
    _HeatmapRackSelection? selectedHeatmapSelection = _selectedHeatmapSelection;

    void zoomBy(double factor, void Function(void Function()) setModalState) {
      final matrix = transformationController.value.clone();
      final currentScale = matrix.getMaxScaleOnAxis();
      final targetScale = (currentScale * factor).clamp(0.6, 3.6).toDouble();
      if (currentScale <= 0) {
        return;
      }
      final applyFactor = targetScale / currentScale;
      matrix.scaleByDouble(applyFactor, applyFactor, 1, 1);
      transformationController.value = matrix;
      setModalState(() {});
    }

    void resetMapView(void Function(void Function()) setModalState) {
      transformationController.value = Matrix4.identity();
      setModalState(() {});
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final currentPosition = _cameraToWorld(
              cameraForward: _cameraForward,
              cameraStrafe: _cameraStrafe,
              geometry: geometry,
            );
            final currentScale = transformationController.value.getMaxScaleOnAxis();
            final activeWaypointIndex = _autoTourRunning && _autoTourUsesCustomWaypoints
                ? (_autoTourWaypointIndex - 1)
                : null;
            final mapWidth = 1300.0;
            final mapHeight = (mapWidth * (geometry.width / geometry.length))
                .clamp(360.0, 820.0)
                .toDouble();
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Lagerübersicht Karte',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Komplette Hallenkarte mit Heatmap, Route und Wegpunkten',
                      style: Theme.of(sheetContext).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Doppeltipp auf ein Rack für Heatmap-Details',
                      style: Theme.of(sheetContext).textTheme.labelMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.52),
                          ),
                          child: InteractiveViewer(
                            transformationController: transformationController,
                            minScale: 0.6,
                            maxScale: 3.6,
                            boundaryMargin: const EdgeInsets.all(240),
                            child: SizedBox(
                              width: mapWidth,
                              height: mapHeight,
                              child: GestureDetector(
                                onTapDown: (details) {
                                  _moveViaMiniMap(
                                    localPosition: details.localPosition,
                                    miniMapSize: Size(mapWidth, mapHeight),
                                    geometry: geometry,
                                    appendRoute: true,
                                  );
                                  setModalState(() {});
                                },
                                onDoubleTapDown: (details) {
                                  final selection = _selectHeatmapRackFromMiniMap(
                                    context: sheetContext,
                                    localPosition: details.localPosition,
                                    miniMapSize: Size(mapWidth, mapHeight),
                                    geometry: geometry,
                                    levelFilter: levelFilter,
                                  );
                                  setModalState(() {
                                    selectedHeatmapSelection = selection;
                                  });
                                },
                                onLongPressStart: (details) {
                                  final world = _miniMapLocalToWorld(
                                    localPosition: details.localPosition,
                                    miniMapSize: Size(mapWidth, mapHeight),
                                    geometry: geometry,
                                  );
                                  _addCustomWaypoint(world, geometry);
                                  setModalState(() {});
                                },
                                child: CustomPaint(
                                  painter: _MiniMapPainter(
                                    geometry: geometry,
                                    position: currentPosition,
                                    heading: _manualYaw,
                                    colorScheme: Theme.of(sheetContext).colorScheme,
                                    route: List<Offset>.unmodifiable(_routeTrail),
                                    waypoints: List<Offset>.unmodifiable(_customTourWaypoints),
                                    activeWaypointIndex: activeWaypointIndex,
                                    selectedRackIndex: _heatmapRackHighlightEnabled
                                        ? selectedHeatmapSelection?.rackIndex
                                        : null,
                                    heatmapVisible: showHeatmapOverlay,
                                    heatmapMetric: widget.heatmapMetric,
                                    heatmapData: widget.heatmapData,
                                    warehouseHeatmapLayer:
                                        widget.warehouseHeatmapLayer,
                                    levelFilter: levelFilter,
                                    totalLevels: _availableShelfLevels,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () => zoomBy(0.85, setModalState),
                          icon: const Icon(Icons.remove),
                          label: const Text('Zoom -'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => resetMapView(setModalState),
                          icon: const Icon(Icons.center_focus_strong_outlined),
                          label: const Text('Reset Ansicht'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => zoomBy(1.18, setModalState),
                          icon: const Icon(Icons.add),
                          label: const Text('Zoom +'),
                        ),
                        Text(
                          'Skalierung ${(currentScale * 100).round()}%',
                          style: Theme.of(sheetContext).textTheme.labelMedium,
                        ),
                        FilterChip(
                          label: Text(showHeatmapOverlay ? 'Heatmap an' : 'Heatmap aus'),
                          selected: showHeatmapOverlay,
                          onSelected: (value) {
                            setModalState(() {
                              showHeatmapOverlay = value;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        ChoiceChip(
                          label: const Text('Alle Ebenen'),
                          selected: levelFilter == -1,
                          onSelected: (_) {
                            setModalState(() {
                              levelFilter = -1;
                            });
                          },
                        ),
                        ...List<Widget>.generate(_availableShelfLevels, (index) {
                          final label = index == 0 ? 'EG' : 'E$index';
                          return ChoiceChip(
                            label: Text(label),
                            selected: levelFilter == index,
                            onSelected: (_) {
                              setModalState(() {
                                levelFilter = index;
                              });
                            },
                          );
                        }),
                      ],
                    ),
                    if (selectedHeatmapSelection != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.9),
                          border: Border.all(
                            color: _heatmapSeverityColor(selectedHeatmapSelection!.heatValue)
                                .withValues(alpha: 0.72),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                selectedHeatmapSelection!.zoneName,
                                style: Theme.of(sheetContext).textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Rack R${selectedHeatmapSelection!.row + 1} - C${selectedHeatmapSelection!.column + 1}',
                                style: Theme.of(sheetContext).textTheme.labelMedium,
                              ),
                              Text(
                                '${_heatmapMetricLabel(widget.heatmapMetric)}: ${(selectedHeatmapSelection!.heatValue * 100).round()}% - ${_heatmapSeverityLabel(selectedHeatmapSelection!.heatValue)}',
                                style: Theme.of(sheetContext).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: const <Widget>[
                        _MapLegendBadge(color: Colors.red, text: 'hoch'),
                        _MapLegendBadge(color: Colors.orange, text: 'mittel'),
                        _MapLegendBadge(color: Colors.green, text: 'niedrig'),
                        _MapLegendBadge(color: Colors.blue, text: 'Wegpunkt'),
                        _MapLegendBadge(color: Colors.deepOrange, text: 'aktiver Wegpunkt'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        FilledButton.tonalIcon(
                          onPressed: _addCustomWaypointAtCurrentPosition,
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: const Text('Wegpunkt hier'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _customTourWaypoints.isEmpty ? null : _removeLastCustomWaypoint,
                          icon: const Icon(Icons.undo),
                          label: const Text('Wegpunkt zurück'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _customTourWaypoints.isEmpty ? null : _clearCustomWaypoints,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Wegpunkte löschen'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    transformationController.dispose();
  }

  void _onMoveStickChanged(Offset offset) {
    if (_autoTourRunning && offset.distance > 0.08) {
      setState(() {
        _stopAutoTour();
      });
    }
    _setMoveInputTarget(
      offset,
      deadZone: 0.06,
      blend: 0.62,
    );
  }

  void _onLookStickChanged(Offset offset) {
    if (_autoTourRunning && offset.distance > 0.08) {
      setState(() {
        _stopAutoTour();
      });
    }
    _setLookInputTarget(
      offset,
      deadZone: 0.06,
      blend: 0.62,
    );
  }

  void _onLiftStickChanged(Offset offset) {
    if (_autoTourRunning && offset.distance > 0.08) {
      setState(() {
        _stopAutoTour();
      });
    }
    _setLiftInputTarget(
      offset,
      deadZone: 0.06,
      blend: 0.62,
    );
  }

  bool _isBlocked(
    Offset point,
    _NavigationGeometry geometry,
    double operatorRadius,
  ) {
    if (point.dx <= operatorRadius ||
        point.dy <= operatorRadius ||
        point.dx >= (geometry.length - operatorRadius) ||
        point.dy >= (geometry.width - operatorRadius)) {
      return true;
    }
    for (var row = 0; row < geometry.rows; row++) {
      final rackY =
          geometry.originY + row * geometry.stepY + ((geometry.stepY - geometry.rackDepth) * 0.5);
      final top = rackY - operatorRadius;
      final bottom = rackY + geometry.rackDepth + operatorRadius;
      if (point.dy <= top || point.dy >= bottom) {
        continue;
      }
      for (var column = 0; column < geometry.columns; column++) {
        final rackX = geometry.originX +
            column * geometry.stepX +
            ((geometry.stepX - geometry.rackLength) * 0.5);
        final left = rackX - operatorRadius;
        final right = rackX + geometry.rackLength + operatorRadius;
        if (point.dx > left && point.dx < right) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topBaseInset =
        MediaQuery.paddingOf(context).top + widget.topOverlayReservedSpace;
    final bottomBaseInset =
        MediaQuery.paddingOf(context).bottom + widget.bottomOverlayReservedSpace;
    final controlBase = widget.cameraToggleBottom
        ? bottomBaseInset + AppSpacing.sm
        : topBaseInset + AppSpacing.sm;
    double? controlTop(double offset) =>
        widget.cameraToggleBottom ? null : controlBase + offset;
    double? controlBottom(double offset) =>
        widget.cameraToggleBottom ? controlBase + offset : null;
    final navGeometry = _navigationGeometry();
    final currentPosition = _cameraToWorld(
      cameraForward: _cameraForward,
      cameraStrafe: _cameraStrafe,
      geometry: navGeometry,
    );
    final visibleMarkers = _visibleInspectionMarkers();
    final routeDistanceMeters = _routeDistanceMeters();
    final activeMiniMapWaypointIndex = _autoTourRunning && _autoTourUsesCustomWaypoints
        ? (_autoTourWaypointIndex - 1)
        : null;
    final topHeatmapHotspots = widget.heatmapVisible
        ? _topHeatmapHotspots(
            geometry: navGeometry,
            levelFilter: -1,
            hotspotFilter: _heatmapHotspotFilter,
            limit: 3,
          )
        : const <_HeatmapRackSelection>[];
    final selectedHotspotTopRank = _selectedHeatmapSelection == null
        ? null
        : (() {
            final index = topHeatmapHotspots.indexWhere(
              (hotspot) => hotspot.rackIndex == _selectedHeatmapSelection!.rackIndex,
            );
            return index < 0 ? null : index + 1;
          })();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Theme.of(context).colorScheme.surfaceContainerHighest,
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                onTapUp: (details) {
                  if (!widget.heatmapVisible) {
                    return;
                  }
                  final renderObject = context.findRenderObject();
                  final viewportSize = renderObject is RenderBox
                      ? renderObject.size
                      : MediaQuery.sizeOf(context);
                  _selectHeatmapRackFromCanvas(
                    context: context,
                    localPosition: details.localPosition,
                    viewportSize: viewportSize,
                    geometry: navGeometry,
                    levelFilter: -1,
                    showFeedback: widget.heatmapVisible,
                  );
                },
                onScaleStart: (details) {
                  _lastScale = 1;
                  _smoothedScaleDelta = 1;
                  _smoothedGestureFocalDelta = Offset.zero;
                  _lastGesturePointerCount = details.pointerCount;
                  _gestureModeBlend = 0;
                  _smoothedPinchForward = 0;
                  _smoothedTwoFingerMove = Offset.zero;
                  if (_cameraMode == _ViewerCameraMode.firstPerson) {
                    _gestureDriveActive = true;
                    if (_autoTourRunning) {
                      setState(() {
                        _stopAutoTour();
                      });
                    }
                  }
                },
                onScaleUpdate: (details) {
                  if (_cameraMode == _ViewerCameraMode.firstPerson) {
                    final pointerCount = details.pointerCount;
                    if (pointerCount != _lastGesturePointerCount) {
                      _lastGesturePointerCount = pointerCount;
                      _smoothedGestureFocalDelta = Offset.zero;
                      _smoothedScaleDelta = 1;
                      _smoothedPinchForward = 0;
                      _smoothedTwoFingerMove = Offset.zero;
                      _lastScale = details.scale <= 0 ? 1 : details.scale;
                    }
                    _smoothedGestureFocalDelta = _blendOffset(
                      _smoothedGestureFocalDelta,
                      details.focalPointDelta,
                      0.32,
                    );
                    if (pointerCount <= 1) {
                      _gestureModeBlend += (0 - _gestureModeBlend) * 0.34;
                      final lookX = _normalizeSignedAxis(
                        _smoothedGestureFocalDelta.dx,
                        divisor: 34,
                        deadZone: 0.02,
                        curve: 1.35,
                      );
                      final lookY = _normalizeSignedAxis(
                        _smoothedGestureFocalDelta.dy,
                        divisor: 34,
                        deadZone: 0.02,
                        curve: 1.35,
                      );
                      _setLookInputTarget(
                        Offset(lookX, lookY),
                        deadZone: 0.038,
                        blend: 0.36,
                      );
                      _smoothedTwoFingerMove = _blendOffset(
                        _smoothedTwoFingerMove,
                        Offset.zero,
                        0.3,
                      );
                      _smoothedPinchForward += (0 - _smoothedPinchForward) * 0.32;
                      _setMoveInputTarget(
                        Offset.zero,
                        deadZone: 0.038,
                        blend: 0.42,
                      );
                      _lastScale = details.scale <= 0 ? 1 : details.scale;
                      _smoothedScaleDelta = 1;
                      return;
                    }

                    _gestureModeBlend += (1 - _gestureModeBlend) * 0.36;
                    final rawScaleDelta = details.scale / (_lastScale == 0 ? 1 : _lastScale);
                    _smoothedScaleDelta += (rawScaleDelta - _smoothedScaleDelta) * 0.22;

                    final pinchRaw = ((_smoothedScaleDelta - 1) * -4.0).clamp(-1.0, 1.0).toDouble();
                    _smoothedPinchForward += (pinchRaw - _smoothedPinchForward) * 0.28;

                    final dragStrafe = _normalizeSignedAxis(
                      _smoothedGestureFocalDelta.dx,
                      divisor: 56,
                      deadZone: 0.03,
                      curve: 1.45,
                    );
                    final dragForward = _normalizeSignedAxis(
                      _smoothedGestureFocalDelta.dy,
                      divisor: 72,
                      deadZone: 0.03,
                      curve: 1.45,
                    );
                    _smoothedTwoFingerMove = _blendOffset(
                      _smoothedTwoFingerMove,
                      Offset(dragStrafe, dragForward),
                      0.3,
                    );

                    final pinchWeight =
                        (_smoothedPinchForward.abs() * 0.75).clamp(0.0, 0.75).toDouble();
                    final dragWeight = (1 - pinchWeight).clamp(0.25, 1.0).toDouble();
                    final strafe = (_smoothedTwoFingerMove.dx *
                            (0.62 + (_gestureModeBlend * 0.18)))
                        .clamp(-1.0, 1.0)
                        .toDouble();
                    final forward = ((_smoothedTwoFingerMove.dy * 0.42 * dragWeight) +
                            (_smoothedPinchForward * 0.92))
                        .clamp(-1.0, 1.0)
                        .toDouble();
                    _setMoveInputTarget(
                      Offset(strafe, forward),
                      deadZone: 0.045,
                      blend: 0.4,
                    );
                    _setLookInputTarget(
                      Offset.zero,
                      deadZone: 0.038,
                      blend: 0.32,
                    );
                    _lastScale = details.scale;
                    return;
                  }
                  if (_cameraMode != _ViewerCameraMode.orbit) {
                    return;
                  }
                  if (details.pointerCount >= 2) {
                    final rawScaleDelta = details.scale / (_lastScale == 0 ? 1 : _lastScale);
                    _smoothedScaleDelta +=
                        (rawScaleDelta - _smoothedScaleDelta) * 0.34;
                    final zoomSensitivity =
                        _sensitivity.zoomFactor * (_precisionMode ? 0.72 : 1.0);
                    const zoomMin = -0.52;
                    const zoomMax = 2.8;
                    final zoomNormalized =
                        ((_targetForward - zoomMin) / (zoomMax - zoomMin)).clamp(0.0, 1.0);
                    final edgeDistance = (zoomNormalized - 0.5).abs() * 2;
                    final edgeDamping = 1 - (edgeDistance * 0.55);
                    _targetForward = (_targetForward +
                            ((_smoothedScaleDelta - 1) *
                                1.12 *
                                zoomSensitivity *
                                edgeDamping))
                        .clamp(-0.52, 2.8)
                        .toDouble();
                    final panFactor =
                        0.0036 * _sensitivity.moveFactor * (_precisionMode ? 0.74 : 1.0);
                    _targetStrafe = (_targetStrafe -
                            (details.focalPointDelta.dx * panFactor))
                        .clamp(-1.8, 1.8)
                        .toDouble();
                    _targetLift = (_targetLift +
                            (details.focalPointDelta.dy * panFactor))
                        .clamp(-0.56, 1.72)
                        .toDouble();
                    _lastScale = details.scale;
                    return;
                  }
                  final orbitFactor = _sensitivity.lookFactor * (_precisionMode ? 0.74 : 1.0);
                  _targetYaw = _normalizeAngle(
                    _targetYaw + ((details.focalPointDelta.dx / 260) * orbitFactor),
                  );
                  _targetPitch = (_targetPitch -
                          ((details.focalPointDelta.dy / 360) * orbitFactor))
                      .clamp(-0.58, 0.58)
                      .toDouble();
                },
                onScaleEnd: (_) {
                  _lastScale = 1;
                  _smoothedScaleDelta = 1;
                  _smoothedGestureFocalDelta = Offset.zero;
                  _lastGesturePointerCount = 0;
                  _gestureModeBlend = 0;
                  _smoothedPinchForward = 0;
                  _smoothedTwoFingerMove = Offset.zero;
                  if (_cameraMode == _ViewerCameraMode.firstPerson &&
                      _gestureDriveActive) {
                    _setLookInputTarget(
                      Offset.zero,
                      deadZone: 0.038,
                      blend: 0.6,
                    );
                    _setMoveInputTarget(
                      Offset.zero,
                      deadZone: 0.038,
                      blend: 0.6,
                    );
                    _gestureDriveActive = false;
                  }
                },
                onDoubleTap: _resetCamera,
                child: RepaintBoundary(
                  child: CustomPaint(
                    isComplex: !_isCameraInMotion,
                    willChange: _isCameraInMotion ||
                        _focusHighlightRemainingS > 0 ||
                        _focusBoostRemainingS > 0 ||
                        (_selectedHeatmapPulseS > 0 && _heatmapRackHighlightEnabled) ||
                        _storageFocusPulseS > 0,
                    painter: _Warehouse3DPainter(
                      colorScheme: colorScheme,
                      warehouse: widget.warehouse,
                      model: widget.model,
                      zonesVisible: widget.zonesVisible,
                      heatmapVisible: widget.heatmapVisible,
                      heatmapMetric: widget.heatmapMetric,
                      heatmapData: widget.heatmapData,
                      cameraDrift: 0,
                      cameraYaw: _manualYaw,
                      cameraPitch: _manualPitch,
                      cameraForward: _cameraForward,
                      cameraStrafe: _cameraStrafe,
                      cameraLift: _cameraLift,
                      isFirstPersonPov: _cameraMode == _ViewerCameraMode.firstPerson &&
                          _traversalMode == _TraversalMode.person,
                      showOperatorAvatar: _cameraMode != _ViewerCameraMode.firstPerson,
                      operatorForward: _cameraForward,
                      operatorStrafe: _cameraStrafe,
                      operatorLift: _cameraLift,
                      renderQuality: _renderQualityHint(),
                      isCameraInMotion: _isCameraInMotion,
                      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                      focusZoneName: _focusedZoneName,
                      focusZonePulse:
                          (_focusHighlightRemainingS / 2.2).clamp(0.0, 1.0).toDouble(),
                      focusRackNumber: _focusedRackNumber,
                      focusLevelNumber: _focusedLevelNumber,
                      focusSlotNumber: _focusedSlotNumber,
                      focusSlotPulse: _focusedRackNumber == null ||
                              _focusedLevelNumber == null ||
                              _focusedSlotNumber == null
                          ? 0
                          : _storageFocusPulseS > 0
                              ? (_storageFocusPulseS / 2.4).clamp(0.25, 1.0).toDouble()
                              : 0.35,
                      selectedRackIndex:
                          _heatmapRackHighlightEnabled ? _selectedHeatmapSelection?.rackIndex : null,
                      selectedRackPulse: _heatmapRackHighlightEnabled
                          ? (_selectedHeatmapPulseS / 2.4).clamp(0.0, 1.0).toDouble()
                          : 0,
                      focusedMarkerId: _focusedMarkerId,
                      inspectionMarkers: visibleMarkers,
                      aisleSpread: _aisleSpread,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            if (_cameraMode == _ViewerCameraMode.firstPerson && _showFpHint)
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: widget.cameraToggleBottom
                    ? bottomBaseInset + 210
                    : bottomBaseInset + 140,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              'First-Person aktiv',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Links bewegen, rechts schauen, zwei Finger = vor/zurück',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.enableFirstPersonControls)
              Positioned(
                top: controlTop(0),
                right: AppSpacing.sm,
                bottom: controlBottom(0),
                child: SegmentedButton<_ViewerCameraMode>(
                  segments: const <ButtonSegment<_ViewerCameraMode>>[
                    ButtonSegment<_ViewerCameraMode>(
                      value: _ViewerCameraMode.orbit,
                      icon: Icon(Icons.threed_rotation),
                      label: Text('Orbit'),
                    ),
                    ButtonSegment<_ViewerCameraMode>(
                      value: _ViewerCameraMode.firstPerson,
                      icon: Icon(Icons.sports_esports_outlined),
                      label: Text('FP'),
                    ),
                  ],
                  selected: <_ViewerCameraMode>{_cameraMode},
                  onSelectionChanged: (value) {
                    setState(() {
                      _cameraMode = value.first;
                      if (_cameraMode != _ViewerCameraMode.firstPerson) {
                        _stopAutoTour();
                      }
                      _forwardVelocity = 0;
                      _strafeVelocity = 0;
                      _liftVelocity = 0;
                      _lookYawVelocity = 0;
                      _lookPitchVelocity = 0;
                      _moveInput = Offset.zero;
                      _lookInput = Offset.zero;
                      _liftInput = Offset.zero;
                      _moveInputTarget = Offset.zero;
                      _lookInputTarget = Offset.zero;
                      _liftInputTarget = Offset.zero;
                      _lastScale = 1;
                      _smoothedScaleDelta = 1;
                      _smoothedGestureFocalDelta = Offset.zero;
                      _lastGesturePointerCount = 0;
                      _gestureModeBlend = 0;
                      _smoothedPinchForward = 0;
                      _smoothedTwoFingerMove = Offset.zero;
                      _targetYaw = _manualYaw;
                      _targetPitch = _manualPitch;
                      _targetForward = _cameraForward;
                      _targetStrafe = _cameraStrafe;
                      _targetLift = _cameraLift;
                      if (_cameraMode == _ViewerCameraMode.firstPerson &&
                          _traversalMode == _TraversalMode.person) {
                        _targetLift = 0.12;
                      }
                    });
                    if (_cameraMode == _ViewerCameraMode.firstPerson) {
                      _triggerFpHint();
                    }
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      colorScheme.surface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            if (widget.enableFirstPersonControls)
              Positioned(
                top: controlTop(224),
                right: AppSpacing.sm,
                bottom: controlBottom(224),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Tooltip(
                          message: 'Gänge schmaler',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove),
                            onPressed: _aisleSpread <= 1.0
                                ? null
                                : () => setState(() {
                                      _aisleSpread = (_aisleSpread - 0.25)
                                          .clamp(1.0, 2.5)
                                          .toDouble();
                                    }),
                          ),
                        ),
                        Tooltip(
                          message: 'Gang-Breite zurücksetzen',
                          child: InkWell(
                            onTap: () => setState(() => _aisleSpread = 1.0),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.swap_horiz,
                                    size: 16,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_aisleSpread.toStringAsFixed(2)}×',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Gänge breiter',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add),
                            onPressed: _aisleSpread >= 2.5
                                ? null
                                : () => setState(() {
                                      _aisleSpread = (_aisleSpread + 0.25)
                                          .clamp(1.0, 2.5)
                                          .toDouble();
                                    }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (widget.enableFirstPersonControls &&
                widget.showOperatorPanel &&
                _cameraMode == _ViewerCameraMode.firstPerson)
              Positioned(
                top: topBaseInset + AppSpacing.sm,
                left: AppSpacing.sm,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                _traversalMode == _TraversalMode.person
                                    ? Icons.person_pin_circle_outlined
                                    : Icons.rocket_launch_outlined,
                                size: 16,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                _traversalMode == _TraversalMode.person
                                    ? 'Mitarbeiter aktiv'
                                    : 'Fly-Modus aktiv',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Position: X ${_worldXFromCamera().toStringAsFixed(1)} m, Y ${_worldYFromCamera().toStringAsFixed(1)} m',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'Blickrichtung: ${_headingLabel()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (_routeTrail.length > 1)
                            Text(
                              'Route: ${routeDistanceMeters.toStringAsFixed(1)} m',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          Text(
                            'Wegpunkte: ${_customTourWaypoints.length}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          if (_autoTourRunning && _autoTourWaypoints.isNotEmpty)
                            Text(
                              '${_autoTourUsesCustomWaypoints ? 'Custom' : 'Auto'}-Rundgang aktiv: Punkt ${_autoTourWaypointIndex + 1}/${_autoTourWaypoints.length}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          Text(
                            'Mini-Map: tippen oder ziehen für Zielposition',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            'Mini-Map lang drücken: Wegpunkt setzen',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            'Mini-Map doppelt tippen: Heatmap-Details',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            '3D-Bild tippen: Heatmap-Hotspot',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            'Touch: 1 Finger schauen, 2 Finger bewegen/zoomen',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            _precisionMode
                                ? 'Präzisionsmodus aktiv (feine Steuerung)'
                                : 'Präzisionsmodus aus',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          if (_selectedHeatmapSelection != null)
                            Text(
                              'Heatmap-Fokus: ${_selectedHeatmapSelection!.zoneName} - '
                              '${_heatmapMetricLabel(widget.heatmapMetric)} '
                              '${(_selectedHeatmapSelection!.heatValue * 100).round()}% '
                              '(${_heatmapSeverityLabel(_selectedHeatmapSelection!.heatValue)})',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: _heatmapSeverityColor(
                                      _selectedHeatmapSelection!.heatValue,
                                    ),
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (_selectedHeatmapSelection != null)
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: <Widget>[
                                _PresetChip(
                                  label: 'Fokus löschen',
                                  onTap: _clearSelectedHeatmapRack,
                                ),
                                _PresetChip(
                                  label: 'Nächster Hotspot',
                                  onTap: () => _focusNextHeatmapHotspot(
                                    context,
                                    navGeometry,
                                  ),
                                ),
                                _PresetChip(
                                  label: _heatmapRackHighlightEnabled
                                      ? 'Highlight aus'
                                      : 'Highlight an',
                                  onTap: () {
                                    setState(() {
                                      _heatmapRackHighlightEnabled =
                                          !_heatmapRackHighlightEnabled;
                                    });
                                  },
                                  active: _heatmapRackHighlightEnabled,
                                ),
                              ],
                            ),
                          if (_selectedHeatmapSelection != null)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _heatmapSeverityColor(
                                    _selectedHeatmapSelection!.heatValue,
                                  ).withValues(alpha: 0.78),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.xs),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      'Hotspot-Details',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      _selectedHeatmapSelection!.zoneName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    Text(
                                      'Rack: R${_selectedHeatmapSelection!.row + 1} / C${_selectedHeatmapSelection!.column + 1}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    Text(
                                      '${_heatmapMetricLabel(widget.heatmapMetric)}: ${(_selectedHeatmapSelection!.heatValue * 100).round()}%',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    Text(
                                      'Schweregrad: ${_heatmapSeverityLabel(_selectedHeatmapSelection!.heatValue)}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (selectedHotspotTopRank != null)
                                      Text(
                                        'Top-Rang: $selectedHotspotTopRank/${topHeatmapHotspots.length}',
                                        style: Theme.of(context).textTheme.labelSmall,
                                      ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Wrap(
                                      spacing: AppSpacing.xs,
                                      runSpacing: AppSpacing.xs,
                                      children: <Widget>[
                                        _PresetChip(
                                          label: 'Zentrieren',
                                          onTap: () => _moveToWorldPosition(
                                            worldPosition:
                                                _selectedHeatmapSelection!.worldCenter,
                                            geometry: navGeometry,
                                            appendRoute: true,
                                          ),
                                        ),
                                        _PresetChip(
                                          label: 'Pulse',
                                          onTap: () {
                                            setState(() {
                                              _selectedHeatmapPulseS = 2.4;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (widget.heatmapVisible)
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: <Widget>[
                                _PresetChip(
                                  label: _hotspotFilterLabel(_HeatmapHotspotFilter.critical),
                                  onTap: () {
                                    setState(() {
                                      _heatmapHotspotFilter =
                                          _HeatmapHotspotFilter.critical;
                                    });
                                  },
                                  active: _heatmapHotspotFilter ==
                                      _HeatmapHotspotFilter.critical,
                                ),
                                _PresetChip(
                                  label: _hotspotFilterLabel(_HeatmapHotspotFilter.high),
                                  onTap: () {
                                    setState(() {
                                      _heatmapHotspotFilter = _HeatmapHotspotFilter.high;
                                    });
                                  },
                                  active:
                                      _heatmapHotspotFilter == _HeatmapHotspotFilter.high,
                                ),
                                _PresetChip(
                                  label: _hotspotFilterLabel(_HeatmapHotspotFilter.all),
                                  onTap: () {
                                    setState(() {
                                      _heatmapHotspotFilter = _HeatmapHotspotFilter.all;
                                    });
                                  },
                                  active:
                                      _heatmapHotspotFilter == _HeatmapHotspotFilter.all,
                                ),
                              ],
                            ),
                          if (topHeatmapHotspots.isNotEmpty)
                            Text(
                              'Top-Hotspots',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          if (topHeatmapHotspots.isNotEmpty)
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: <Widget>[
                                for (var i = 0; i < topHeatmapHotspots.length; i++)
                                  _PresetChip(
                                    label: 'H${i + 1} ${(topHeatmapHotspots[i].heatValue * 100).round()}%',
                                    onTap: () => _focusHeatmapHotspotSelection(
                                      context: context,
                                      geometry: navGeometry,
                                      selection: topHeatmapHotspots[i],
                                      rank: i + 1,
                                      total: topHeatmapHotspots.length,
                                    ),
                                    active: _selectedHeatmapSelection?.rackIndex ==
                                        topHeatmapHotspots[i].rackIndex,
                                  ),
                              ],
                            ),
                          if (widget.heatmapVisible && topHeatmapHotspots.isEmpty)
                            Text(
                              'Keine Hotspots im Filter ${_hotspotFilterLabel(_heatmapHotspotFilter)}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          if (_recentHeatmapSelections.isNotEmpty)
                            Text(
                              'Zuletzt angesehene Hotspots',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          if (_recentHeatmapSelections.isNotEmpty)
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: <Widget>[
                                for (final recent in _recentHeatmapSelections)
                                  _PresetChip(
                                    label:
                                        'R${recent.row + 1}/C${recent.column + 1} ${(recent.heatValue * 100).round()}%',
                                    onTap: () => _focusHeatmapHotspotSelection(
                                      context: context,
                                      geometry: navGeometry,
                                      selection: recent,
                                    ),
                                    active: _selectedHeatmapSelection?.rackIndex ==
                                        recent.rackIndex,
                                  ),
                                _PresetChip(
                                  label: 'Verlauf löschen',
                                  onTap: _clearRecentHeatmapSelections,
                                ),
                              ],
                            ),
                          const SizedBox(height: AppSpacing.xs),
                          SizedBox(
                            height: 110,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final miniMapSize = Size(constraints.maxWidth, 110);
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: GestureDetector(
                                    onTapDown: (details) => _moveViaMiniMap(
                                      localPosition: details.localPosition,
                                      miniMapSize: miniMapSize,
                                      geometry: navGeometry,
                                      appendRoute: true,
                                    ),
                                    onPanStart: (details) => _moveViaMiniMap(
                                      localPosition: details.localPosition,
                                      miniMapSize: miniMapSize,
                                      geometry: navGeometry,
                                      appendRoute: true,
                                    ),
                                    onPanUpdate: (details) => _moveViaMiniMap(
                                      localPosition: details.localPosition,
                                      miniMapSize: miniMapSize,
                                      geometry: navGeometry,
                                      appendRoute: true,
                                    ),
                                    onLongPressStart: (details) {
                                      final world = _miniMapLocalToWorld(
                                        localPosition: details.localPosition,
                                        miniMapSize: miniMapSize,
                                        geometry: navGeometry,
                                      );
                                      _addCustomWaypoint(world, navGeometry);
                                    },
                                    onDoubleTapDown: (details) {
                                      _selectHeatmapRackFromMiniMap(
                                        context: context,
                                        localPosition: details.localPosition,
                                        miniMapSize: miniMapSize,
                                        geometry: navGeometry,
                                        levelFilter: -1,
                                      );
                                    },
                                    child: CustomPaint(
                                      painter: _MiniMapPainter(
                                        geometry: navGeometry,
                                        position: currentPosition,
                                        heading: _manualYaw,
                                        colorScheme: colorScheme,
                                        route: List<Offset>.unmodifiable(_routeTrail),
                                        waypoints:
                                            List<Offset>.unmodifiable(_customTourWaypoints),
                                        activeWaypointIndex: activeMiniMapWaypointIndex,
                                        selectedRackIndex: _heatmapRackHighlightEnabled
                                            ? _selectedHeatmapSelection?.rackIndex
                                            : null,
                                        heatmapVisible: widget.heatmapVisible,
                                        heatmapMetric: widget.heatmapMetric,
                                        heatmapData: widget.heatmapData,
                                        warehouseHeatmapLayer:
                                            widget.warehouseHeatmapLayer,
                                        levelFilter: -1,
                                        totalLevels: _availableShelfLevels,
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: <Widget>[
                              _PresetChip(
                                label: 'Gesamt',
                                onTap: () => _applyPreset(_CameraPreset.overall),
                              ),
                              _PresetChip(
                                label: 'Tor',
                                onTap: () => _applyPreset(_CameraPreset.dock),
                              ),
                              _PresetChip(
                                label: 'Gang',
                                onTap: () => _applyPreset(_CameraPreset.aisle),
                              ),
                              _PresetChip(
                                label: _autoTourRunning
                                    ? 'Auto-Rundgang stoppen'
                                    : 'Auto-Rundgang starten',
                                onTap: _toggleAutoTour,
                                active: _autoTourRunning,
                              ),
                              _PresetChip(
                                label: 'Wegpunkt +',
                                onTap: _addCustomWaypointAtCurrentPosition,
                              ),
                              if (_customTourWaypoints.isNotEmpty)
                                _PresetChip(
                                  label: 'Wegpunkt -',
                                  onTap: _removeLastCustomWaypoint,
                                ),
                              if (_customTourWaypoints.isNotEmpty)
                                _PresetChip(
                                  label: 'Wegpunkte löschen',
                                  onTap: _clearCustomWaypoints,
                                ),
                              _PresetChip(
                                label: _autoTourRunning && _autoTourUsesCustomWaypoints
                                    ? 'Custom-Rundgang stoppen'
                                    : 'Custom-Rundgang starten',
                                onTap: () => _toggleCustomAutoTour(context),
                                active: _autoTourRunning && _autoTourUsesCustomWaypoints,
                              ),
                              _PresetChip(
                                label: 'Lagerkarte',
                                onTap: () => _openWarehouseOverviewMap(context),
                              ),
                              if (_routeTrail.length > 1)
                                _PresetChip(
                                  label: 'Route löschen',
                                  onTap: _clearRouteTrail,
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: <Widget>[
                              _PresetChip(
                                label: 'Inspektion +',
                                onTap: _addInspectionMarker,
                              ),
                              if (_inspectionMarkers.isNotEmpty)
                                _PresetChip(
                                  label: 'Inspektionen',
                                  onTap: () => _openMarkerManager(context),
                                ),
                              if (_inspectionMarkers.isNotEmpty)
                                _PresetChip(
                                  label: 'Nächster',
                                  onTap: () => _focusNextInspectionMarker(
                                    context,
                                    visibleMarkers,
                                  ),
                                ),
                              if (_inspectionMarkers.isNotEmpty)
                                _PresetChip(
                                  label: 'Undo',
                                  onTap: _undoInspectionMarker,
                                ),
                              if (_inspectionMarkers.length > 1)
                                _PresetChip(
                                  label: 'Clear',
                                  onTap: _clearInspectionMarkers,
                                ),
                              if (_inspectionMarkers.isNotEmpty)
                                _PresetChip(
                                  label: 'JSON',
                                  onTap: () => _exportInspectionMarkers(context),
                                ),
                              if (_inspectionMarkers.isNotEmpty)
                                _PresetChip(
                                  label: 'Tabelle',
                                  onTap: () => _exportInspectionMarkersCsv(context),
                                ),
                            ],
                          ),
                          Text(
                            'Inspektionen: ${visibleMarkers.length}/${_inspectionMarkers.length}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.enableFirstPersonControls)
              Positioned(
                top: topBaseInset + 58,
                right: AppSpacing.sm,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: PopupMenuButton<_ViewerSensitivity>(
                    initialValue: _sensitivity,
                    tooltip: 'Kamera-Empfindlichkeit',
                    onSelected: (value) {
                      setState(() {
                        _sensitivity = value;
                      });
                    },
                    itemBuilder: (context) => _ViewerSensitivity.values
                        .map(
                          (value) => CheckedPopupMenuItem<_ViewerSensitivity>(
                            value: value,
                            checked: _sensitivity == value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(growable: false),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.tune, size: 16),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            _sensitivity.label,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.enableFirstPersonControls &&
                _cameraMode == _ViewerCameraMode.firstPerson &&
                widget.cameraToggleBottom)
              Positioned(
                right: AppSpacing.sm,
                bottom: controlBottom(56),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'FP Steuerung',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        SegmentedButton<_TraversalMode>(
                          segments: const <ButtonSegment<_TraversalMode>>[
                            ButtonSegment<_TraversalMode>(
                              value: _TraversalMode.person,
                              icon: Icon(Icons.person_outline),
                              label: Text('Person'),
                            ),
                            ButtonSegment<_TraversalMode>(
                              value: _TraversalMode.fly,
                              icon: Icon(Icons.flight_takeoff),
                              label: Text('Fly'),
                            ),
                          ],
                          selected: <_TraversalMode>{_traversalMode},
                          onSelectionChanged: (value) {
                            setState(() {
                              _traversalMode = value.first;
                              if (_traversalMode != _TraversalMode.person) {
                                _stopAutoTour();
                              }
                              _liftInput = Offset.zero;
                              _liftInputTarget = Offset.zero;
                              _liftVelocity = 0;
                              if (_traversalMode == _TraversalMode.person) {
                                _targetLift = 0.12;
                              }
                            });
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStatePropertyAll(
                              colorScheme.surface.withValues(alpha: 0.9),
                            ),
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        SegmentedButton<_TraversalSpeed>(
                          segments: <ButtonSegment<_TraversalSpeed>>[
                            ButtonSegment<_TraversalSpeed>(
                              value: _TraversalSpeed.slow,
                              icon: const Icon(Icons.directions_walk_outlined),
                              label: Text(_TraversalSpeed.slow.label),
                            ),
                            ButtonSegment<_TraversalSpeed>(
                              value: _TraversalSpeed.normal,
                              icon: const Icon(Icons.directions_run),
                              label: Text(_TraversalSpeed.normal.label),
                            ),
                            ButtonSegment<_TraversalSpeed>(
                              value: _TraversalSpeed.sprint,
                              icon: const Icon(Icons.flash_on_outlined),
                              label: Text(_TraversalSpeed.sprint.label),
                            ),
                          ],
                          selected: <_TraversalSpeed>{_traversalSpeed},
                          onSelectionChanged: (value) {
                            setState(() {
                              _traversalSpeed = value.first;
                            });
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStatePropertyAll(
                              colorScheme.surface.withValues(alpha: 0.9),
                            ),
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() {
                              _precisionMode = !_precisionMode;
                            });
                          },
                          icon: Icon(
                            _precisionMode
                                ? Icons.tune_rounded
                                : Icons.tune_outlined,
                          ),
                          label: Text(_precisionMode ? 'Präzise' : 'Normal'),
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _showJoysticks = !_showJoysticks;
                            });
                          },
                          icon: Icon(
                            _showJoysticks
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          label: Text(
                            _showJoysticks ? 'Steuerung aus' : 'Steuerung an',
                          ),
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (widget.enableFirstPersonControls &&
                _cameraMode == _ViewerCameraMode.firstPerson &&
                !widget.cameraToggleBottom)
              Positioned(
                top: controlTop(56),
                right: AppSpacing.sm,
                bottom: controlBottom(56),
                child: SegmentedButton<_TraversalMode>(
                  segments: const <ButtonSegment<_TraversalMode>>[
                    ButtonSegment<_TraversalMode>(
                      value: _TraversalMode.person,
                      icon: Icon(Icons.person_outline),
                      label: Text('Person'),
                    ),
                    ButtonSegment<_TraversalMode>(
                      value: _TraversalMode.fly,
                      icon: Icon(Icons.flight_takeoff),
                      label: Text('Fly'),
                    ),
                  ],
                  selected: <_TraversalMode>{_traversalMode},
                  onSelectionChanged: (value) {
                    setState(() {
                      _traversalMode = value.first;
                      if (_traversalMode != _TraversalMode.person) {
                        _stopAutoTour();
                      }
                      _liftInput = Offset.zero;
                      _liftInputTarget = Offset.zero;
                      _liftVelocity = 0;
                      if (_traversalMode == _TraversalMode.person) {
                        _targetLift = 0.12;
                      }
                    });
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      colorScheme.surface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            if (widget.enableFirstPersonControls &&
                _cameraMode == _ViewerCameraMode.firstPerson &&
                !widget.cameraToggleBottom)
              Positioned(
                top: controlTop(112),
                right: AppSpacing.sm,
                bottom: controlBottom(112),
                child: SegmentedButton<_TraversalSpeed>(
                  segments: <ButtonSegment<_TraversalSpeed>>[
                    ButtonSegment<_TraversalSpeed>(
                      value: _TraversalSpeed.slow,
                      icon: const Icon(Icons.directions_walk_outlined),
                      label: Text(_TraversalSpeed.slow.label),
                    ),
                    ButtonSegment<_TraversalSpeed>(
                      value: _TraversalSpeed.normal,
                      icon: const Icon(Icons.directions_run),
                      label: Text(_TraversalSpeed.normal.label),
                    ),
                    ButtonSegment<_TraversalSpeed>(
                      value: _TraversalSpeed.sprint,
                      icon: const Icon(Icons.flash_on_outlined),
                      label: Text(_TraversalSpeed.sprint.label),
                    ),
                  ],
                  selected: <_TraversalSpeed>{_traversalSpeed},
                  onSelectionChanged: (value) {
                    setState(() {
                      _traversalSpeed = value.first;
                    });
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      colorScheme.surface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            if (widget.enableFirstPersonControls &&
                _cameraMode == _ViewerCameraMode.firstPerson &&
                !widget.cameraToggleBottom)
              Positioned(
                top: controlTop(168),
                right: AppSpacing.sm,
                bottom: controlBottom(168),
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() {
                      _precisionMode = !_precisionMode;
                    });
                  },
                  icon: Icon(
                    _precisionMode
                        ? Icons.tune_rounded
                        : Icons.tune_outlined,
                  ),
                  label: Text(_precisionMode ? 'Präzise' : 'Normal'),
                ),
              ),
            if (widget.enableFirstPersonControls &&
                _cameraMode == _ViewerCameraMode.firstPerson &&
                (_showJoysticks || !widget.cameraToggleBottom))
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runAlignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    _VirtualJoystick(
                      icon: Icons.open_with_rounded,
                      label: 'Bewegen',
                      onChanged: _onMoveStickChanged,
                    ),
                    if (_traversalMode == _TraversalMode.fly)
                      _VirtualJoystick(
                        icon: Icons.unfold_more_rounded,
                        label: 'Höhe',
                        axis: _JoystickAxis.vertical,
                        onChanged: _onLiftStickChanged,
                      ),
                    _VirtualJoystick(
                      icon: Icons.control_camera_outlined,
                      label: 'Blick',
                      onChanged: _onLookStickChanged,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FocusSlotData {
  const _FocusSlotData({
    required this.rackIndex,
    required this.levelNumber,
    required this.slotNumber,
    required this.slotMax,
  });

  final int rackIndex;
  final int levelNumber;
  final int slotNumber;
  final int slotMax;
}

class _Warehouse3DPainter extends CustomPainter {
  const _Warehouse3DPainter({
    required this.colorScheme,
    required this.warehouse,
    required this.model,
    required this.zonesVisible,
    required this.heatmapVisible,
    required this.heatmapMetric,
    required this.heatmapData,
    required this.cameraDrift,
    required this.cameraYaw,
    required this.cameraPitch,
    required this.cameraForward,
    required this.cameraStrafe,
    required this.cameraLift,
    required this.isFirstPersonPov,
    required this.showOperatorAvatar,
    required this.operatorForward,
    required this.operatorStrafe,
    required this.operatorLift,
    required this.renderQuality,
    required this.isCameraInMotion,
    required this.devicePixelRatio,
    required this.focusZoneName,
    required this.focusZonePulse,
    required this.focusRackNumber,
    required this.focusLevelNumber,
    required this.focusSlotNumber,
    required this.focusSlotPulse,
    required this.selectedRackIndex,
    required this.selectedRackPulse,
    required this.focusedMarkerId,
    required this.inspectionMarkers,
    this.aisleSpread = 1.0,
  });

  final ColorScheme colorScheme;
  final Warehouse warehouse;
  final WarehouseModelData? model;
  final bool zonesVisible;
  final bool heatmapVisible;
  final ViewerHeatmapMetric heatmapMetric;
  final List<ViewerHeatmapEntry> heatmapData;
  final double cameraDrift;
  final double cameraYaw;
  final double cameraPitch;
  final double cameraForward;
  final double cameraStrafe;
  final double cameraLift;
  final bool isFirstPersonPov;
  final bool showOperatorAvatar;
  final double operatorForward;
  final double operatorStrafe;
  final double operatorLift;
  final _RenderQuality renderQuality;
  final bool isCameraInMotion;
  final double devicePixelRatio;
  final String? focusZoneName;
  final double focusZonePulse;
  final int? focusRackNumber;
  final int? focusLevelNumber;
  final int? focusSlotNumber;
  final double focusSlotPulse;
  final int? selectedRackIndex;
  final double selectedRackPulse;
  final String? focusedMarkerId;
  final List<_InspectionMarker> inspectionMarkers;
  // Gang-Breiten-Faktor (nur visuell); muss identisch zu _navigationGeometry()
  // im State sein, damit Render- und Klick-Geometrie deckungsgleich bleiben.
  final double aisleSpread;

  @override
  void paint(Canvas canvas, Size size) {
    final base = _resolveBase();
    final rackArea = _resolveRackArea(base);
    final projection = _Projection(
      base: base,
      size: size,
      cameraDrift: cameraDrift,
      cameraYaw: cameraYaw,
      cameraPitch: cameraPitch,
      cameraForward: cameraForward,
      cameraStrafe: cameraStrafe,
      cameraLift: cameraLift,
      isFirstPersonPov: isFirstPersonPov,
    );
    final quality = _effectiveRenderQuality();
    final rackCount = base.rows * base.columns;
    var lowPower = switch (quality) {
      _RenderQuality.quality => false,
      _RenderQuality.balanced => rackCount > 240 || projection.scale < 7.2,
      _RenderQuality.performance => rackCount > 110 || projection.scale < 9.0,
      _RenderQuality.auto => rackCount > 240 || projection.scale < 7.2,
    };
    var ultraLowPower = switch (quality) {
      _RenderQuality.quality => false,
      _RenderQuality.balanced => rackCount > 360 || projection.scale < 5.8,
      _RenderQuality.performance => rackCount > 170 || projection.scale < 7.4,
      _RenderQuality.auto => rackCount > 360 || projection.scale < 5.8,
    };
    if (isCameraInMotion) {
      lowPower = true;
      ultraLowPower = ultraLowPower || rackCount > 120 || projection.scale < 8.6;
    }

    _paintBackground(canvas, size);
    _paintBuildingShell(canvas, projection, base);
    _paintFloor(canvas, projection, base);
    if (!ultraLowPower) {
      _paintInboundDock(canvas, projection, base);
    }
    if (!lowPower) {
      _paintConveyorSystem(canvas, projection, base, rackArea);
      _paintForkliftAreas(canvas, projection, base, rackArea);
      _paintStagingPallets(canvas, projection, base, rackArea);
    }
    _paintShelves(
      canvas,
      projection,
      base,
      rackArea,
      lowPower: lowPower,
      ultraLowPower: ultraLowPower,
    );
    _paintFocusZoneHighlight(canvas, projection, base);
    _paintInspectionMarkers(canvas, projection, base);
    if (showOperatorAvatar) {
      _paintOperatorAvatar(canvas, projection, base);
    }
    if (zonesVisible) {
      _paintZones(canvas, projection, base);
    }
    _paintInfo(canvas, size, base);
  }

  _Warehouse3DBase _resolveBase() {
    final layout = warehouse.layoutSpec;
    const megaLengthFactor = 1.72;
    const megaWidthFactor = 1.58;
    const megaHeightFactor = 1.22;
    // Gang-Breiten-Faktor skaliert nur die Grundflaeche (Laenge/Breite), nicht
    // die Hoehe. Muss identisch zu _navigationGeometry() sein, damit Render- und
    // Klick-Geometrie deckungsgleich bleiben.
    final aisle = aisleSpread;
    final fallbackLength = (model?.warehouseLengthM ?? layout?.lengthM ?? 70) * megaLengthFactor * aisle;
    final fallbackWidth = (model?.warehouseWidthM ?? layout?.widthM ?? 42) * megaWidthFactor * aisle;
    final fallbackHeight = (model?.warehouseHeightM ?? layout?.heightM ?? 14) * megaHeightFactor;

    final baseRows = (model?.shelfRows ?? layout?.rackRowCount ?? 8).clamp(2, 18);
    final baseColumns = (model?.shelfColumns ?? 10).clamp(3, 26);
    final baseLevels = (model?.shelfLevels ?? layout?.rackLevels ?? 4).clamp(2, 10);
    final quality = _effectiveRenderQuality();
    final rows = switch (quality) {
      _RenderQuality.quality => (baseRows * 1.36).round().clamp(4, 28),
      _RenderQuality.balanced => (baseRows * 1.26).round().clamp(4, 20),
      _RenderQuality.performance => (baseRows * 1.0).round().clamp(4, 14),
      _RenderQuality.auto => (baseRows * 1.26).round().clamp(4, 20),
    };
    final columns = switch (quality) {
      _RenderQuality.quality => (baseColumns * 1.42).round().clamp(6, 40),
      _RenderQuality.balanced => (baseColumns * 1.28).round().clamp(6, 28),
      _RenderQuality.performance => (baseColumns * 1.0).round().clamp(6, 18),
      _RenderQuality.auto => (baseColumns * 1.28).round().clamp(6, 28),
    };
    final levels = switch (quality) {
      _RenderQuality.quality => (baseLevels * 1.24).round().clamp(3, 10),
      _RenderQuality.balanced => (baseLevels * 1.15).round().clamp(3, 8),
      _RenderQuality.performance => (baseLevels * 1.0).round().clamp(3, 5),
      _RenderQuality.auto => (baseLevels * 1.15).round().clamp(3, 8),
    };
    return _Warehouse3DBase(
      length: fallbackLength,
      width: fallbackWidth,
      height: fallbackHeight,
      rows: rows,
      columns: columns,
      levels: levels,
      zones: model?.zones ?? const <WarehouseModelZone>[],
    );
  }

  _RackAreaMetrics _resolveRackArea(_Warehouse3DBase base) {
    final rackAreaLength = base.length * 0.86;
    final rackAreaWidth = base.width * 0.76;
    final originX = (base.length - rackAreaLength) * 0.5;
    final originY = (base.width - rackAreaWidth) * 0.5;
    final stepX = rackAreaLength / base.columns;
    final stepY = rackAreaWidth / base.rows;

    return _RackAreaMetrics(
      originX: originX,
      originY: originY,
      areaLength: rackAreaLength,
      areaWidth: rackAreaWidth,
      stepX: stepX,
      stepY: stepY,
      // Regalgroesse absolut konstant halten (durch /aisle kompensiert), damit
      // beim Aufziehen der Gaenge nur der Abstand waechst, nicht die Regale.
      rackLength: (stepX / aisleSpread) * 0.66,
      rackDepth: (stepY / aisleSpread) * 0.34,
      rackHeight: (base.height * 0.74).clamp(9.0, 22.0),
    );
  }

  _FocusSlotData? _resolveFocusSlotData(_Warehouse3DBase base) {
    final rackNumber = focusRackNumber;
    final levelNumber = focusLevelNumber;
    final slotNumber = focusSlotNumber;
    if (rackNumber == null || levelNumber == null || slotNumber == null) {
      return null;
    }
    final rackCount = base.rows * base.columns;
    if (rackCount <= 0) {
      return null;
    }
    final safeRack = rackNumber.clamp(1, rackCount);
    final safeLevel = levelNumber.clamp(1, base.levels);
    final slotMax = _resolveSlotMax(base, rackCount);
    final safeSlot = slotNumber.clamp(1, slotMax);
    return _FocusSlotData(
      rackIndex: safeRack - 1,
      levelNumber: safeLevel,
      slotNumber: safeSlot,
      slotMax: slotMax,
    );
  }

  int _resolveSlotMax(_Warehouse3DBase base, int rackCount) {
    final modelSlots = model?.shelfColumns ?? 0;
    if (modelSlots > 0) {
      return modelSlots;
    }
    final total = warehouse.totalStorageSlots;
    final divisor = rackCount * base.levels;
    if (total > 0 && divisor > 0) {
      return math.max(1, (total / divisor).round());
    }
    return 12;
  }

  void _paintBackground(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
          colorScheme.surface,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
  }

  void _paintFloor(Canvas canvas, _Projection projection, _Warehouse3DBase base) {
    final p0 = projection.project(0, 0, 0);
    final p1 = projection.project(base.length, 0, 0);
    final p2 = projection.project(base.length, base.width, 0);
    final p3 = projection.project(0, base.width, 0);

    final floor = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();

    canvas.drawPath(
      floor,
      Paint()..color = colorScheme.surfaceContainerLow,
    );
    final stripePaint = Paint()
      ..color = colorScheme.onSurface.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final t = i / 8;
      final a = projection.project(base.length * t, 0, 0.02);
      final b = projection.project(base.length * t, base.width, 0.02);
      canvas.drawLine(a, b, stripePaint);
    }
    if (_isElringLayoutProfile()) {
      final hallSeparatorPaint = Paint()
        ..color = colorScheme.onSurface.withValues(alpha: 0.28)
        ..strokeWidth = 2.0;
      for (final ratio in <double>[0.34, 0.62]) {
        final x = base.length * ratio;
        final a = projection.project(x, 0, 0.08);
        final b = projection.project(x, base.width, 0.08);
        canvas.drawLine(a, b, hallSeparatorPaint);
      }
      final inboundStartY = base.width * 0.80;
      final inboundPath = Path()
        ..moveTo(
          projection.project(0, inboundStartY, 0.06).dx,
          projection.project(0, inboundStartY, 0.06).dy,
        )
        ..lineTo(
          projection.project(base.length, inboundStartY, 0.06).dx,
          projection.project(base.length, inboundStartY, 0.06).dy,
        )
        ..lineTo(
          projection.project(base.length, base.width, 0.06).dx,
          projection.project(base.length, base.width, 0.06).dy,
        )
        ..lineTo(
          projection.project(0, base.width, 0.06).dx,
          projection.project(0, base.width, 0.06).dy,
        )
        ..close();
      canvas.drawPath(
        inboundPath,
        Paint()..color = Colors.amber.withValues(alpha: 0.12),
      );
      canvas.drawLine(
        projection.project(0, inboundStartY, 0.09),
        projection.project(base.length, inboundStartY, 0.09),
        Paint()
          ..color = Colors.amber.withValues(alpha: 0.55)
          ..strokeWidth = 2,
      );
    }
    canvas.drawPath(
      floor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = colorScheme.outline.withValues(alpha: 0.55),
    );
  }

  void _paintBuildingShell(
    Canvas canvas,
    _Projection projection,
    _Warehouse3DBase base,
  ) {
    final wallHeight = base.height * 1.02;

    final rearA = projection.project(0, 0, 0);
    final rearB = projection.project(base.length, 0, 0);
    final rearC = projection.project(base.length, 0, wallHeight);
    final rearD = projection.project(0, 0, wallHeight);
    final rearPath = Path()
      ..moveTo(rearA.dx, rearA.dy)
      ..lineTo(rearB.dx, rearB.dy)
      ..lineTo(rearC.dx, rearC.dy)
      ..lineTo(rearD.dx, rearD.dy)
      ..close();
    canvas.drawPath(
      rearPath,
      Paint()..color = colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
    );

    final sideA = projection.project(0, 0, 0);
    final sideB = projection.project(0, base.width, 0);
    final sideC = projection.project(0, base.width, wallHeight);
    final sideD = projection.project(0, 0, wallHeight);
    final sidePath = Path()
      ..moveTo(sideA.dx, sideA.dy)
      ..lineTo(sideB.dx, sideB.dy)
      ..lineTo(sideC.dx, sideC.dy)
      ..lineTo(sideD.dx, sideD.dy)
      ..close();
    canvas.drawPath(
      sidePath,
      Paint()..color = colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
    );

    final framePaint = Paint()
      ..color = colorScheme.onSurface.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 0; i <= 8; i++) {
      final t = i / 8;
      final a = projection.project(base.length * t, 0, 0);
      final b = projection.project(base.length * t, 0, wallHeight);
      canvas.drawLine(a, b, framePaint);
    }
    for (var i = 0; i <= 4; i++) {
      final t = i / 4;
      final a = projection.project(0, 0, wallHeight * t);
      final b = projection.project(base.length, 0, wallHeight * t);
      canvas.drawLine(a, b, framePaint);
    }

    final gateCount = _isElringLayoutProfile() ? 20 : 4;
    final startRatio = _isElringLayoutProfile() ? 0.04 : 0.12;
    final spanRatio = _isElringLayoutProfile() ? 0.92 : 0.72;
    final gateSpan = base.length * spanRatio;
    final gateSlotWidth = gateSpan / gateCount;
    final gateWidth = gateSlotWidth * (_isElringLayoutProfile() ? 0.68 : 0.74);
    for (var i = 0; i < gateCount; i++) {
      final x0 = (base.length * startRatio) + (i * gateSlotWidth) + ((gateSlotWidth - gateWidth) * 0.5);
      final x1 = x0 + gateWidth;
      final z0 = 0.4;
      final z1 = wallHeight * 0.38;
      _drawQuad(
        canvas: canvas,
        a: projection.project(x0, 0.01, z0),
        b: projection.project(x1, 0.01, z0),
        c: projection.project(x1, 0.01, z1),
        d: projection.project(x0, 0.01, z1),
        fill: colorScheme.surface.withValues(alpha: 0.65),
        stroke: colorScheme.onSurface.withValues(alpha: 0.2),
      );
    }

    for (var i = 0; i < 7; i++) {
      final t = (i + 0.5) / 7;
      final lightPos = projection.project(base.length * t, base.width * 0.5, wallHeight * 0.94);
      canvas.drawCircle(
        lightPos,
        2.8,
        Paint()..color = Colors.amber.withValues(alpha: 0.85),
      );
      canvas.drawCircle(
        lightPos,
        8,
        Paint()..color = Colors.amber.withValues(alpha: 0.16),
      );
    }
  }

  void _paintShelves(
    Canvas canvas,
    _Projection projection,
    _Warehouse3DBase base,
    _RackAreaMetrics rackArea,
    {
    required bool lowPower,
    required bool ultraLowPower,
    }
  ) {
    final rackAreaLength = rackArea.areaLength;
    final rackAreaWidth = rackArea.areaWidth;
    final originX = rackArea.originX;
    final originY = rackArea.originY;
    final stepX = rackArea.stepX;
    final stepY = rackArea.stepY;
    final rackLength = rackArea.rackLength;
    final rackDepth = rackArea.rackDepth;
    final rackHeight = rackArea.rackHeight;
    final focusSlotData = focusSlotPulse > 0 ? _resolveFocusSlotData(base) : null;

    final aislePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = colorScheme.onSurface.withValues(alpha: 0.16);
    final aisleStep = (base.rows > 18 || projection.scale < 8.2) ? 2 : 1;
    for (var row = aisleStep; row < base.rows; row += aisleStep) {
      final y = originY + row * stepY;
      final p0 = projection.project(originX, y, 0.05);
      final p1 = projection.project(originX + rackAreaLength, y, 0.05);
      canvas.drawLine(p0, p1, aislePaint);
    }
    final safetyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.amber.withValues(alpha: 0.55);
    final laneTopA = projection.project(originX, originY, 0.08);
    final laneTopB = projection.project(originX + rackAreaLength, originY, 0.08);
    final laneBottomA = projection.project(originX, originY + rackAreaWidth, 0.08);
    final laneBottomB =
        projection.project(originX + rackAreaLength, originY + rackAreaWidth, 0.08);
    canvas.drawLine(laneTopA, laneTopB, safetyPaint);
    canvas.drawLine(laneBottomA, laneBottomB, safetyPaint);
    for (var i = 0; i < 4; i++) {
      final tx = (i + 1) / 5;
      final x = originX + (rackAreaLength * tx);
      _drawFloorArrow(canvas, projection, x: x, y: originY + (stepY * 0.5), size: stepY * 0.42);
    }

    final rackCount = base.rows * base.columns;
    final slotColumns = ultraLowPower
        ? 2
        : rackCount > 180
            ? 2
            : rackCount > 100
                ? 3
                : 4;
    final shownLevels = ultraLowPower
        ? base.levels.clamp(2, 4)
        : lowPower
            ? base.levels.clamp(2, 5)
            : (base.levels > 7 ? 7 : base.levels);
    final cameraWorld = Offset(
      ((base.length * 0.5) + (cameraStrafe * base.length * 0.36))
          .clamp(0.0, base.length)
          .toDouble(),
      ((base.width * 0.5) + (cameraForward * base.width * 0.56))
          .clamp(0.0, base.width)
          .toDouble(),
    );
    final detailNearDistance = (isFirstPersonPov ? stepX * 8.0 : stepX * 11.0);
    final detailMidDistance = detailNearDistance * (ultraLowPower ? 1.4 : 1.8);
    final denseScene = rackCount > 260 || projection.scale < 7.0;
    final hasSelectedRack = selectedRackIndex != null || focusSlotData != null;
    final rowStep = hasSelectedRack ? 1 : (ultraLowPower && !isFirstPersonPov ? 2 : 1);
    final colStep = hasSelectedRack ? 1 : (ultraLowPower && !isFirstPersonPov ? 2 : 1);
    final offscreenMargin = isFirstPersonPov ? 120.0 : 180.0;

    for (var row = 0; row < base.rows; row += rowStep) {
      for (var column = 0; column < base.columns; column += colStep) {
        final rawRackIndex = (row * base.columns) + column;
        final isSelected = selectedRackIndex == rawRackIndex;
        final isFocusRack = focusSlotData?.rackIndex == rawRackIndex;
        final x = originX + column * stepX + (stepX - rackLength) * 0.5;
        final y = originY + row * stepY + (stepY - rackDepth) * 0.5;
        final value = _heatValue(row, column, base.rows, base.columns);
        final center = Offset(x + (rackLength * 0.5), y + (rackDepth * 0.5));
        final distance = (center - cameraWorld).distance;
        final projectedCenter =
            projection.project(center.dx, center.dy, rackHeight * 0.34);
        if (_isProjectedOutsideViewport(
          projectedCenter,
          projection.size,
          margin: offscreenMargin,
        )) {
          continue;
        }
        var detail = distance <= detailNearDistance
            ? _RackRenderDetail.high
            : distance <= detailMidDistance
                ? _RackRenderDetail.medium
                : _RackRenderDetail.low;
        if (isCameraInMotion && detail == _RackRenderDetail.high) {
          detail = _RackRenderDetail.medium;
        }
        if (isCameraInMotion &&
            detail == _RackRenderDetail.medium &&
            distance > detailNearDistance * 0.9) {
          detail = _RackRenderDetail.low;
        }
        if (!isSelected &&
            !isFocusRack &&
            denseScene &&
            detail == _RackRenderDetail.low &&
            !isFirstPersonPov &&
            ((row + column).isOdd)) {
          continue;
        }
        if (!isSelected &&
            !isFocusRack &&
            isCameraInMotion &&
            detail == _RackRenderDetail.low &&
            !isFirstPersonPov &&
            ((row + (column * 2)) % 3 != 0)) {
          continue;
        }
        if (isFocusRack && detail == _RackRenderDetail.low) {
          detail = _RackRenderDetail.medium;
        }
        _drawHighBayRack(
          canvas: canvas,
          projection: projection,
          x: x,
          y: y,
          w: rackLength,
          d: rackDepth,
          h: rackHeight,
          rackRow: row,
          rackColumn: column,
          levels: shownLevels.clamp(2, 10),
          slotColumns: slotColumns,
          heatValue: value,
          detail: detail,
          focusSlotData: isFocusRack ? focusSlotData : null,
          focusPulse: isFocusRack ? focusSlotPulse : 0,
        );
        if (isSelected) {
          _paintSelectedRackHighlight(
            canvas: canvas,
            projection: projection,
            x: x,
            y: y,
            w: rackLength,
            d: rackDepth,
            h: rackHeight,
          );
        }
      }
    }
  }

  void _paintSelectedRackHighlight({
    required Canvas canvas,
    required _Projection projection,
    required double x,
    required double y,
    required double w,
    required double d,
    required double h,
  }) {
    final pulseT = (1 - selectedRackPulse).clamp(0.0, 1.0).toDouble();
    final wave = (math.sin((pulseT * math.pi * 6) + 0.6) + 1) * 0.5;
    final baseAlpha = (0.18 + (selectedRackPulse * 0.36)).clamp(0.0, 0.72).toDouble();
    final strokeAlpha = (baseAlpha + (wave * 0.22)).clamp(0.0, 0.9).toDouble();
    final glowAlpha = (0.10 + (wave * 0.18)).clamp(0.0, 0.45).toDouble();

    final z = h * 0.62;
    final p0 = projection.project(x, y, z);
    final p1 = projection.project(x + w, y, z);
    final p2 = projection.project(x + w, y + d, z);
    final p3 = projection.project(x, y + d, z);
    final ring = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();

    canvas.drawPath(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = colorScheme.primary.withValues(alpha: strokeAlpha),
    );
    canvas.drawPath(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: (strokeAlpha + 0.08).clamp(0.0, 0.95)),
    );

    final center = projection.project(x + (w * 0.5), y + (d * 0.5), z + (h * 0.08));
    canvas.drawCircle(
      center,
      7.0 + (wave * 3.4),
      Paint()..color = colorScheme.primary.withValues(alpha: glowAlpha),
    );
    canvas.drawCircle(
      center,
      3.1,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  _RenderQuality _effectiveRenderQuality() {
    if (renderQuality != _RenderQuality.auto) {
      return renderQuality;
    }
    if (isCameraInMotion) {
      return _RenderQuality.performance;
    }
    if (heatmapVisible && devicePixelRatio >= 1.8) {
      return _RenderQuality.performance;
    }
    if (kIsWeb) {
      if (devicePixelRatio >= 2.0) {
        return _RenderQuality.performance;
      }
      return _RenderQuality.balanced;
    }
    if (devicePixelRatio >= 2.3) {
      return _RenderQuality.performance;
    }
    if (devicePixelRatio >= 1.7) {
      return _RenderQuality.balanced;
    }
    return _RenderQuality.quality;
  }

  void _paintInboundDock(Canvas canvas, _Projection projection, _Warehouse3DBase base) {
    final dockY0 = base.width * 0.88;
    final dockY1 = base.width * 0.985;
    final dockX0 = base.length * 0.08;
    final dockX1 = base.length * 0.92;
    final operatorX = ((base.length * 0.5) + (operatorStrafe * base.length * 0.36))
        .clamp(0.0, base.length)
        .toDouble();
    final operatorY = ((base.width * 0.5) + (operatorForward * base.width * 0.56))
        .clamp(0.0, base.width)
        .toDouble();

    _drawQuad(
      canvas: canvas,
      a: projection.project(dockX0, dockY0, 0.11),
      b: projection.project(dockX1, dockY0, 0.11),
      c: projection.project(dockX1, dockY1, 0.11),
      d: projection.project(dockX0, dockY1, 0.11),
      fill: colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
      stroke: colorScheme.outline.withValues(alpha: 0.42),
    );

    final stripCount = 18;
    for (var i = 0; i < stripCount; i++) {
      if (i.isOdd) {
        continue;
      }
      final t0 = i / stripCount;
      final t1 = (i + 1) / stripCount;
      final x0 = dockX0 + ((dockX1 - dockX0) * t0);
      final x1 = dockX0 + ((dockX1 - dockX0) * t1);
      _drawQuad(
        canvas: canvas,
        a: projection.project(x0, dockY1 - (base.width * 0.012), 0.12),
        b: projection.project(x1, dockY1 - (base.width * 0.012), 0.12),
        c: projection.project(x1, dockY1, 0.12),
        d: projection.project(x0, dockY1, 0.12),
        fill: Colors.amber.withValues(alpha: 0.56),
        stroke: Colors.amber.withValues(alpha: 0.18),
      );
    }

    final gateCount = 6;
    for (var gate = 0; gate < gateCount; gate++) {
      final t = (gate + 0.5) / gateCount;
      final xCenter = dockX0 + ((dockX1 - dockX0) * t);
      final gateW = (dockX1 - dockX0) / gateCount * 0.62;
      final gx0 = xCenter - (gateW / 2);
      final gx1 = xCenter + (gateW / 2);
      final proximityX = ((operatorX - xCenter).abs() / (gateW * 1.35)).clamp(0.0, 1.0);
      final proximityY =
          ((operatorY - (dockY0 + (base.width * 0.028))).abs() / (base.width * 0.17))
              .clamp(0.0, 1.0);
      final openAmount = (1 - math.sqrt((proximityX * proximityX) + (proximityY * proximityY)))
          .clamp(0.0, 1.0)
          .toDouble();

      final gateBaseZ = 0.13;
      final gateHeight = (base.height * 0.26).clamp(1.8, 4.8);
      final doorBottomZ = gateBaseZ + (gateHeight * openAmount);
      final doorTopZ = gateBaseZ + gateHeight;

      _drawQuad(
        canvas: canvas,
        a: projection.project(gx0, dockY0 + (base.width * 0.008), gateBaseZ),
        b: projection.project(gx1, dockY0 + (base.width * 0.008), gateBaseZ),
        c: projection.project(gx1, dockY0 + (base.width * 0.008), gateBaseZ + gateHeight),
        d: projection.project(gx0, dockY0 + (base.width * 0.008), gateBaseZ + gateHeight),
        fill: colorScheme.surface.withValues(alpha: 0.22),
        stroke: colorScheme.onSurface.withValues(alpha: 0.20),
      );
      _drawQuad(
        canvas: canvas,
        a: projection.project(gx0, dockY0 + (base.width * 0.012), doorBottomZ),
        b: projection.project(gx1, dockY0 + (base.width * 0.012), doorBottomZ),
        c: projection.project(gx1, dockY0 + (base.width * 0.012), doorTopZ),
        d: projection.project(gx0, dockY0 + (base.width * 0.012), doorTopZ),
        fill: Color.alphaBlend(
          Colors.white.withValues(alpha: 0.08),
          colorScheme.primary.withValues(alpha: 0.58),
        ),
        stroke: colorScheme.primary.withValues(alpha: 0.32),
      );

      final sensorPos = projection.project(
        xCenter,
        dockY0 + (base.width * 0.01),
        gateBaseZ + gateHeight + 0.08,
      );
      canvas.drawCircle(
        sensorPos,
        2.6,
        Paint()
          ..color = Color.lerp(
                Colors.orangeAccent.shade700,
                Colors.greenAccent.shade400,
                openAmount,
              )!
              .withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        sensorPos,
        6.2,
        Paint()
          ..color = Color.lerp(
                Colors.orangeAccent.shade700,
                Colors.greenAccent.shade400,
                openAmount,
              )!
              .withValues(alpha: 0.18),
      );
    }
  }

  void _paintConveyorSystem(
    Canvas canvas,
    _Projection projection,
    _Warehouse3DBase base,
    _RackAreaMetrics rackArea,
  ) {
    final conveyorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colorScheme.primary.withValues(alpha: 0.68);
    final lineGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = colorScheme.primary.withValues(alpha: 0.13);

    final startY = base.width * 0.9;
    final endY = rackArea.originY + (rackArea.areaWidth * 0.06);
    final lineCount = 4;

    for (var i = 0; i < lineCount; i++) {
      final t = (i + 1) / (lineCount + 1);
      final x = rackArea.originX + (rackArea.areaLength * t);
      final a = projection.project(x, startY, 0.16);
      final b = projection.project(x, endY, 0.16);
      canvas.drawLine(a, b, lineGlow);
      canvas.drawLine(a, b, conveyorPaint);

      for (var box = 0; box < 3; box++) {
        final bt = (box + 1) / 4;
        final packageY = startY + ((endY - startY) * bt);
        final packageW = rackArea.stepX * 0.22;
        final packageD = rackArea.stepY * 0.2;
        _drawBox(
          canvas: canvas,
          projection: projection,
          x: x - (packageW / 2),
          y: packageY - (packageD / 2),
          z: 0.16,
          w: packageW,
          d: packageD,
          h: (base.height * 0.018).clamp(0.24, 0.8),
          color: Colors.blueGrey.withValues(alpha: 0.86),
        );
      }
    }
  }

  void _paintForkliftAreas(
    Canvas canvas,
    _Projection projection,
    _Warehouse3DBase base,
    _RackAreaMetrics rackArea,
  ) {
    final zoneWidth = base.length * 0.09;
    final zoneDepth = rackArea.areaWidth * 0.9;
    final leftX = rackArea.originX - (zoneWidth * 0.84);
    final rightX = rackArea.originX + rackArea.areaLength - (zoneWidth * 0.16);
    final zoneY = rackArea.originY + (rackArea.areaWidth * 0.05);

    _drawHazardZone(
      canvas: canvas,
      projection: projection,
      x: leftX,
      y: zoneY,
      w: zoneWidth,
      d: zoneDepth,
      label: 'FZ-1',
    );
    _drawHazardZone(
      canvas: canvas,
      projection: projection,
      x: rightX,
      y: zoneY,
      w: zoneWidth,
      d: zoneDepth,
      label: 'FZ-2',
    );

    final routePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.amber.shade700.withValues(alpha: 0.66);
    for (var i = 0; i < 5; i++) {
      final t = (i + 1) / 6;
      final y = zoneY + (zoneDepth * t);
      canvas.drawLine(
        projection.project(leftX + zoneWidth, y, 0.1),
        projection.project(rightX, y, 0.1),
        routePaint,
      );
    }
  }

  void _drawHazardZone({
    required Canvas canvas,
    required _Projection projection,
    required double x,
    required double y,
    required double w,
    required double d,
    required String label,
  }) {
    _drawQuad(
      canvas: canvas,
      a: projection.project(x, y, 0.1),
      b: projection.project(x + w, y, 0.1),
      c: projection.project(x + w, y + d, 0.1),
      d: projection.project(x, y + d, 0.1),
      fill: Colors.amber.withValues(alpha: 0.11),
      stroke: Colors.amber.withValues(alpha: 0.55),
    );

    const stripes = 10;
    for (var i = 0; i < stripes; i++) {
      final t0 = i / stripes;
      final t1 = (i + 0.5) / stripes;
      _drawQuad(
        canvas: canvas,
        a: projection.project(x + (w * t0), y + (d * 0.02), 0.11),
        b: projection.project(x + (w * t1), y + (d * 0.02), 0.11),
        c: projection.project(x + (w * (t1 + 0.08)), y + (d * 0.18), 0.11),
        d: projection.project(x + (w * (t0 + 0.08)), y + (d * 0.18), 0.11),
        fill: (i.isEven ? Colors.black : Colors.amber).withValues(alpha: 0.42),
        stroke: Colors.transparent,
      );
    }

    _paintLabel(
      canvas,
      label,
      projection.project(x + (w * 0.5), y + (d * 0.5), 0.18),
    );
  }

  void _paintStagingPallets(
    Canvas canvas,
    _Projection projection,
    _Warehouse3DBase base,
    _RackAreaMetrics rackArea,
  ) {
    final blocks = <({double x, double y, int stacks})>[
      (x: rackArea.originX + (rackArea.areaLength * 0.08), y: base.width * 0.83, stacks: 3),
      (x: rackArea.originX + (rackArea.areaLength * 0.44), y: base.width * 0.835, stacks: 4),
      (x: rackArea.originX + (rackArea.areaLength * 0.78), y: base.width * 0.84, stacks: 3),
    ];
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      for (var i = 0; i < block.stacks; i++) {
        final px = block.x + (i * rackArea.stepX * 0.18);
        final py = block.y + ((i.isEven ? 0.0 : 1.0) * rackArea.stepY * 0.06);
        _drawBox(
          canvas: canvas,
          projection: projection,
          x: px,
          y: py,
          z: 0.11,
          w: rackArea.stepX * 0.14,
          d: rackArea.stepY * 0.24,
          h: (base.height * 0.035).clamp(0.34, 1.0),
          color: const Color(0xFF8D6E63),
        );
        _drawBox(
          canvas: canvas,
          projection: projection,
          x: px + (rackArea.stepX * 0.012),
          y: py + (rackArea.stepY * 0.02),
          z: 0.11 + (base.height * 0.035).clamp(0.34, 1.0),
          w: rackArea.stepX * 0.116,
          d: rackArea.stepY * 0.19,
          h: (base.height * 0.04).clamp(0.45, 1.25),
          color: switch ((index + i) % 3) {
            0 => Colors.deepOrange.withValues(alpha: 0.85),
            1 => Colors.blueGrey.withValues(alpha: 0.85),
            _ => Colors.indigo.withValues(alpha: 0.85),
          },
        );
      }
    }
  }

  void _paintZones(Canvas canvas, _Projection projection, _Warehouse3DBase base) {
    if (base.zones.isEmpty) {
      return;
    }
    final zoneColors = <Color>[
      Colors.lightBlue.shade400.withValues(alpha: 0.20),
      Colors.orange.shade400.withValues(alpha: 0.20),
      Colors.green.shade400.withValues(alpha: 0.20),
      Colors.red.shade300.withValues(alpha: 0.20),
    ];

    for (var i = 0; i < base.zones.length; i++) {
      final zone = base.zones[i];
      final left = (zone.x.clamp(0, 1) * base.length).toDouble();
      final top = (zone.y.clamp(0, 1) * base.width).toDouble();
      final width = (zone.width.clamp(0.05, 1) * base.length).toDouble();
      final height = (zone.height.clamp(0.05, 1) * base.width).toDouble();
      final color = zoneColors[i % zoneColors.length];

      final p0 = projection.project(left, top, 0.12);
      final p1 = projection.project(left + width, top, 0.12);
      final p2 = projection.project(left + width, top + height, 0.12);
      final p3 = projection.project(left, top + height, 0.12);

      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..close();

      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = color.withValues(alpha: 0.7),
      );

      final labelPos = projection.project(
        left + width * 0.5,
        top + height * 0.5,
        0.2,
      );
      _paintLabel(canvas, zone.name, labelPos);
    }
  }

  void _paintFocusZoneHighlight(
    Canvas canvas,
    _Projection projection,
    _Warehouse3DBase base,
  ) {
    final zoneName = focusZoneName?.trim();
    if (zoneName == null || zoneName.isEmpty || base.zones.isEmpty || focusZonePulse <= 0) {
      return;
    }
    final normalized = zoneName.toLowerCase();
    WarehouseModelZone? target;
    for (final zone in base.zones) {
      if (zone.name.trim().toLowerCase() == normalized) {
        target = zone;
        break;
      }
    }
    target ??= () {
      for (final zone in base.zones) {
        final name = zone.name.trim().toLowerCase();
        if (name.contains(normalized) || normalized.contains(name)) {
          return zone;
        }
      }
      return null;
    }();
    if (target == null) {
      return;
    }

    final left = (target.x.clamp(0, 1) * base.length).toDouble();
    final top = (target.y.clamp(0, 1) * base.width).toDouble();
    final width = (target.width.clamp(0.05, 1) * base.length).toDouble();
    final height = (target.height.clamp(0.05, 1) * base.width).toDouble();
    final pulse = (math.sin(focusZonePulse * math.pi * 4) + 1) * 0.5;
    final baseAlpha = (0.24 + (focusZonePulse * 0.28)).clamp(0.0, 0.62).toDouble();
    final strokeAlpha = (0.52 + (pulse * 0.38)).clamp(0.0, 0.98).toDouble();
    final strokeWidth = 1.4 + (pulse * 1.6);

    final p0 = projection.project(left, top, 0.2);
    final p1 = projection.project(left + width, top, 0.2);
    final p2 = projection.project(left + width, top + height, 0.2);
    final p3 = projection.project(left, top + height, 0.2);
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = colorScheme.primary.withValues(alpha: baseAlpha),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = Colors.orange.withValues(alpha: strokeAlpha),
    );

    final labelPos = projection.project(
      left + width * 0.5,
      top + height * 0.5,
      0.36,
    );
    _paintLabel(canvas, 'Fokus: ${target.name}', labelPos);
  }

  void _paintInfo(Canvas canvas, Size size, _Warehouse3DBase base) {
    final label = '${warehouse.name} - ${base.rows} x ${base.columns}';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: size.width - (AppSpacing.md * 2));

    final left = AppSpacing.sm;
    final top = AppSpacing.sm;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left - 6, top - 4, textPainter.width + 12, textPainter.height + 8),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = colorScheme.surface.withValues(alpha: 0.82),
    );
    textPainter.paint(canvas, Offset(left, top));
  }

  void _paintOperatorAvatar(
    Canvas canvas,
    _Projection projection,
    _Warehouse3DBase base,
  ) {
    final x = ((base.length * 0.5) + (operatorStrafe * base.length * 0.36))
        .clamp(base.length * 0.04, base.length * 0.96)
        .toDouble();
    final y = ((base.width * 0.5) + (operatorForward * base.width * 0.56))
        .clamp(base.width * 0.04, base.width * 0.96)
        .toDouble();
    final z = (operatorLift * base.height * 0.72).clamp(0.0, base.height * 0.7).toDouble();

    final bodyW = (base.length / base.columns * 0.12).clamp(0.28, 0.68).toDouble();
    final bodyD = (base.width / base.rows * 0.12).clamp(0.24, 0.62).toDouble();
    final legH = (base.height * 0.035).clamp(0.44, 0.95).toDouble();
    final torsoH = (base.height * 0.048).clamp(0.55, 1.22).toDouble();
    final bodyX = x - (bodyW / 2);
    final bodyY = y - (bodyD / 2);

    _drawBox(
      canvas: canvas,
      projection: projection,
      x: bodyX,
      y: bodyY,
      z: z + 0.02,
      w: bodyW,
      d: bodyD,
      h: legH,
      color: const Color(0xFF1E293B).withValues(alpha: 0.95),
    );
    _drawBox(
      canvas: canvas,
      projection: projection,
      x: bodyX - (bodyW * 0.05),
      y: bodyY - (bodyD * 0.05),
      z: z + legH,
      w: bodyW * 1.1,
      d: bodyD * 1.1,
      h: torsoH,
      color: colorScheme.primary.withValues(alpha: 0.92),
    );

    final head = projection.project(x, y, z + legH + torsoH + (bodyW * 0.75));
    canvas.drawCircle(
      head,
      3.4,
      Paint()..color = const Color(0xFFF1C27D).withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      head,
      5.8,
      Paint()..color = colorScheme.primary.withValues(alpha: 0.16),
    );

    _paintLabel(
      canvas,
      'Du',
      projection.project(x, y, z + legH + torsoH + (bodyW * 1.25)),
    );
  }

  void _paintInspectionMarkers(
    Canvas canvas,
    _Projection projection,
    _Warehouse3DBase base,
  ) {
    for (final marker in inspectionMarkers) {
      final x = ((base.length * 0.5) + (marker.strafe * base.length * 0.36))
          .clamp(0.0, base.length)
          .toDouble();
      final y = ((base.width * 0.5) + (marker.forward * base.width * 0.56))
          .clamp(0.0, base.width)
          .toDouble();
      final z =
          ((marker.lift * base.height * 0.72) + 0.1).clamp(0.0, base.height * 0.8).toDouble();
      final color = marker.type.color();
      final statusAlpha = switch (marker.status) {
        _InspectionStatus.open => 0.98,
        _InspectionStatus.inReview => 0.78,
        _InspectionStatus.closed => 0.52,
      };
      final glowAlpha = switch (marker.status) {
        _InspectionStatus.open => 0.22,
        _InspectionStatus.inReview => 0.18,
        _InspectionStatus.closed => 0.12,
      };
      final radius = switch (marker.priority) {
        _InspectionPriority.low => 3.8,
        _InspectionPriority.medium => 4.5,
        _InspectionPriority.high => 5.1,
      };
      final isOverdue = _isMarkerOverdue(marker);
      final isFocused = marker.id == focusedMarkerId;
      final markerRadius = isFocused ? radius * 1.34 : radius;
      final markerGlow = isFocused ? glowAlpha + 0.16 : glowAlpha;

      final origin = projection.project(x, y, z);
      canvas.drawCircle(
        origin,
        markerRadius,
        Paint()..color = color.withValues(alpha: statusAlpha),
      );
      canvas.drawCircle(
        origin,
        markerRadius * 2.2,
        Paint()..color = color.withValues(alpha: markerGlow.clamp(0.0, 0.5)),
      );
      if (isFocused) {
        canvas.drawCircle(
          origin,
          markerRadius * 2.9,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = colorScheme.primary.withValues(alpha: 0.74),
        );
      }
      _paintLabel(
        canvas,
        '${isFocused ? 'FOKUS - ' : ''}${marker.type.label} - ${marker.status.label}${isOverdue ? ' - OVERDUE' : ''}',
        projection.project(x, y, z + 0.35),
      );
    }
  }

  bool _isMarkerOverdue(_InspectionMarker marker) {
    final dueDate = marker.dueDate;
    if (dueDate == null || marker.status == _InspectionStatus.closed) {
      return false;
    }
    final now = DateTime.now();
    final dueDateEnd = DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
      23,
      59,
      59,
      999,
    );
    return now.isAfter(dueDateEnd);
  }

  void _paintLabel(Canvas canvas, String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: 90);

    final offset = Offset(center.dx - painter.width / 2, center.dy - painter.height / 2);
    final backdrop = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        offset.dx - 4,
        offset.dy - 2,
        painter.width + 8,
        painter.height + 4,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      backdrop,
      Paint()..color = colorScheme.surface.withValues(alpha: 0.72),
    );
    painter.paint(canvas, offset);
  }

  void _drawBox({
    required Canvas canvas,
    required _Projection projection,
    required double x,
    required double y,
    required double z,
    required double w,
    required double d,
    required double h,
    required Color color,
  }) {
    final p000 = projection.project(x, y, z);
    final p100 = projection.project(x + w, y, z);
    final p010 = projection.project(x, y + d, z);
    final p110 = projection.project(x + w, y + d, z);

    final p001 = projection.project(x, y, z + h);
    final p101 = projection.project(x + w, y, z + h);
    final p011 = projection.project(x, y + d, z + h);
    final p111 = projection.project(x + w, y + d, z + h);

    final top = Path()
      ..moveTo(p001.dx, p001.dy)
      ..lineTo(p101.dx, p101.dy)
      ..lineTo(p111.dx, p111.dy)
      ..lineTo(p011.dx, p011.dy)
      ..close();
    final sideRight = Path()
      ..moveTo(p100.dx, p100.dy)
      ..lineTo(p110.dx, p110.dy)
      ..lineTo(p111.dx, p111.dy)
      ..lineTo(p101.dx, p101.dy)
      ..close();
    final sideLeft = Path()
      ..moveTo(p000.dx, p000.dy)
      ..lineTo(p001.dx, p001.dy)
      ..lineTo(p011.dx, p011.dy)
      ..lineTo(p010.dx, p010.dy)
      ..close();

    canvas.drawPath(top, Paint()..color = Color.alphaBlend(Colors.white.withValues(alpha: 0.24), color));
    canvas.drawPath(
      sideRight,
      Paint()..color = Color.alphaBlend(Colors.black.withValues(alpha: 0.22), color),
    );
    canvas.drawPath(
      sideLeft,
      Paint()..color = Color.alphaBlend(Colors.black.withValues(alpha: 0.10), color),
    );

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = colorScheme.outline.withValues(alpha: 0.42);
    canvas.drawPath(top, edge);
    canvas.drawPath(sideRight, edge);
    canvas.drawPath(sideLeft, edge);
  }

  void _drawHighBayRack({
    required Canvas canvas,
    required _Projection projection,
    required double x,
    required double y,
    required double w,
    required double d,
    required double h,
    required int rackRow,
    required int rackColumn,
    required int levels,
    required int slotColumns,
    required double heatValue,
    required _RackRenderDetail detail,
    _FocusSlotData? focusSlotData,
    double focusPulse = 0,
  }) {
    final effectiveDetail = isCameraInMotion && detail == _RackRenderDetail.high
        ? _RackRenderDetail.medium
        : detail;
    final frameBase = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.10),
      colorScheme.surfaceContainerHighest,
    );
    _drawBox(
      canvas: canvas,
      projection: projection,
      x: x,
      y: y,
      z: 0,
      w: w,
      d: d,
      h: h,
      color: frameBase,
    );

    if (effectiveDetail == _RackRenderDetail.low) {
      final z = h * 0.52;
      final frontA = projection.project(x, y, z);
      final frontB = projection.project(x + w, y, z);
      canvas.drawLine(
        frontA,
        frontB,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.95
          ..color = colorScheme.onSurface.withValues(alpha: 0.24),
      );
      return;
    }

    final postPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.95
      ..color = colorScheme.onSurface.withValues(alpha: 0.45);
    final beamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = colorScheme.onSurface.withValues(alpha: 0.28);

    final posts = <(Offset, Offset)>[
      (projection.project(x, y, 0), projection.project(x, y, h)),
      (projection.project(x + w, y, 0), projection.project(x + w, y, h)),
      (projection.project(x, y + d, 0), projection.project(x, y + d, h)),
      (projection.project(x + w, y + d, 0), projection.project(x + w, y + d, h)),
    ];
    for (final post in posts) {
      canvas.drawLine(post.$1, post.$2, postPaint);
    }

    final safeLevels = switch (effectiveDetail) {
      _RackRenderDetail.medium => levels.clamp(2, 5),
      _RackRenderDetail.high => levels.clamp(2, 7),
      _RackRenderDetail.low => 2,
    };
    for (var level = 1; level < safeLevels; level++) {
      final z = (h / safeLevels) * level;
      final frontA = projection.project(x, y, z);
      final frontB = projection.project(x + w, y, z);
      final backA = projection.project(x, y + d, z);
      final backB = projection.project(x + w, y + d, z);
      canvas.drawLine(frontA, frontB, beamPaint);
      canvas.drawLine(backA, backB, beamPaint);
    }
    if (effectiveDetail == _RackRenderDetail.high) {
      final bracePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = colorScheme.onSurface.withValues(alpha: 0.22);
      for (var level = 0; level < safeLevels - 1; level += 2) {
        final z0 = (h / safeLevels) * level;
        final z1 = (h / safeLevels) * (level + 1);
        final a = projection.project(x, y, z0);
        final b = projection.project(x + w, y, z1);
        final c = projection.project(x + w, y, z0);
        final d = projection.project(x, y, z1);
        canvas.drawLine(a, b, bracePaint);
        canvas.drawLine(c, d, bracePaint);
      }
    }

    final safeSlotColumns = switch (effectiveDetail) {
      _RackRenderDetail.medium => slotColumns.clamp(2, 3),
      _RackRenderDetail.high => slotColumns.clamp(2, 4),
      _RackRenderDetail.low => 2,
    };
    final slotW = w / safeSlotColumns;
    final levelH = h / safeLevels;
    for (var level = 0; level < safeLevels; level++) {
      final z0 = (level * levelH) + (levelH * 0.12);
      final z1 = ((level + 1) * levelH) - (levelH * 0.16);
      if (z1 <= z0) {
        continue;
      }
      for (var slot = 0; slot < safeSlotColumns; slot++) {
        final seed = ((rackRow * 97) + (rackColumn * 73) + (level * 31) + (slot * 19)) % 100;
        final variance = seed / 100;
        final occupiedThreshold = heatValue.clamp(0, 1).toDouble();
        final isOccupied = variance <= occupiedThreshold;

        final baseColor = isOccupied
            ? _heatColor((occupiedThreshold * 0.82) + (variance * 0.18))
            : colorScheme.surfaceContainerLow;
        final slotColor = isOccupied
            ? Color.alphaBlend(Colors.white.withValues(alpha: 0.08), baseColor)
            : baseColor.withValues(alpha: 0.8);

        final x0 = x + (slot * slotW) + (slotW * 0.12);
        final x1 = x + ((slot + 1) * slotW) - (slotW * 0.12);
        final yFront = y + (d * 0.05);
        final ySide = y + d;
        _drawQuad(
          canvas: canvas,
          a: projection.project(x0, yFront, z0),
          b: projection.project(x1, yFront, z0),
          c: projection.project(x1, yFront, z1),
          d: projection.project(x0, yFront, z1),
          fill: slotColor.withValues(alpha: isOccupied ? 0.86 : 0.62),
          stroke: colorScheme.onSurface.withValues(alpha: 0.18),
        );
        if (slot == safeSlotColumns - 1 || slot == 0) {
          _drawQuad(
            canvas: canvas,
            a: projection.project(x1, yFront, z0),
            b: projection.project(x1, ySide, z0),
            c: projection.project(x1, ySide, z1),
            d: projection.project(x1, yFront, z1),
            fill: slotColor.withValues(alpha: isOccupied ? 0.48 : 0.30),
            stroke: colorScheme.onSurface.withValues(alpha: 0.12),
          );
        }

        final palletBaseZ = z0 + ((z1 - z0) * 0.04);
        final palletBaseX = x0 + ((x1 - x0) * 0.08);
        final palletBaseW = (x1 - x0) * 0.84;
        final palletBaseY = y + (d * 0.19);
        final palletBaseD = d * 0.56;
        final palletBaseH = (z1 - z0) * 0.08;

        _drawBox(
          canvas: canvas,
          projection: projection,
          x: palletBaseX,
          y: palletBaseY,
          z: palletBaseZ,
          w: palletBaseW,
          d: palletBaseD,
          h: palletBaseH,
          color: const Color(0xFF8D6E63).withValues(alpha: isOccupied ? 0.9 : 0.52),
        );

        if (isOccupied && effectiveDetail == _RackRenderDetail.high) {
          final seedMix = (rackRow * 13) + (rackColumn * 11) + (level * 7) + slot;
          _drawPalletLoad(
            canvas: canvas,
            projection: projection,
            x: palletBaseX + (palletBaseW * 0.04),
            y: palletBaseY + (palletBaseD * 0.04),
            z: palletBaseZ + palletBaseH,
            w: palletBaseW * 0.92,
            d: palletBaseD * 0.92,
            h: (z1 - z0) * 0.46,
            seed: seedMix,
          );
        }
      }
    }

    if (focusSlotData != null && focusPulse > 0) {
      final focusLevelIndex =
          (focusSlotData.levelNumber - 1).clamp(0, safeLevels - 1);
      final normalizedSlot = (focusSlotData.slotNumber - 1) /
          math.max(1, focusSlotData.slotMax);
      final focusSlotIndex =
          (normalizedSlot * safeSlotColumns).floor().clamp(0, safeSlotColumns - 1);
      final slotW = w / safeSlotColumns;
      final levelH = h / safeLevels;
      final z0 = (focusLevelIndex * levelH) + (levelH * 0.12);
      final z1 = ((focusLevelIndex + 1) * levelH) - (levelH * 0.16);
      if (z1 > z0) {
        final x0 = x + (focusSlotIndex * slotW) + (slotW * 0.12);
        final x1 = x + ((focusSlotIndex + 1) * slotW) - (slotW * 0.12);
        final yFront = y + (d * 0.05);
        final glowFill = colorScheme.primary.withValues(
          alpha: (0.12 + (0.18 * focusPulse)).clamp(0.12, 0.36).toDouble(),
        );
        final glowStroke = colorScheme.primary.withValues(
          alpha: (0.45 + (0.35 * focusPulse)).clamp(0.4, 0.85).toDouble(),
        );
        _drawQuad(
          canvas: canvas,
          a: projection.project(x0, yFront, z0),
          b: projection.project(x1, yFront, z0),
          c: projection.project(x1, yFront, z1),
          d: projection.project(x0, yFront, z1),
          fill: glowFill,
          stroke: glowStroke,
        );
        final outline = Path()
          ..moveTo(projection.project(x0, yFront, z0).dx,
              projection.project(x0, yFront, z0).dy)
          ..lineTo(projection.project(x1, yFront, z0).dx,
              projection.project(x1, yFront, z0).dy)
          ..lineTo(projection.project(x1, yFront, z1).dx,
              projection.project(x1, yFront, z1).dy)
          ..lineTo(projection.project(x0, yFront, z1).dx,
              projection.project(x0, yFront, z1).dy)
          ..close();
        canvas.drawPath(
          outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = glowStroke,
        );
        final dot = projection.project(
          (x0 + x1) * 0.5,
          yFront + (d * 0.03),
          z1 + (levelH * 0.12),
        );
        canvas.drawCircle(
          dot,
          4.2,
          Paint()
            ..color = colorScheme.primary.withValues(
              alpha: (0.5 + (0.35 * focusPulse)).clamp(0.4, 0.9).toDouble(),
            ),
        );
      }
    }
  }

  void _drawPalletLoad({
    required Canvas canvas,
    required _Projection projection,
    required double x,
    required double y,
    required double z,
    required double w,
    required double d,
    required double h,
    required int seed,
  }) {
    final loadHeight = h.clamp(0.28, 1.9);
    final color = switch (seed % 5) {
      0 => const Color(0xFFEF6C00),
      1 => const Color(0xFF1976D2),
      2 => const Color(0xFF7B1FA2),
      3 => const Color(0xFF455A64),
      _ => const Color(0xFF43A047),
    };
    _drawBox(
      canvas: canvas,
      projection: projection,
      x: x,
      y: y,
      z: z,
      w: w,
      d: d,
      h: loadHeight,
      color: color.withValues(alpha: 0.9),
    );

    final strapCount = seed.isEven ? 1 : 2;
    for (var i = 0; i < strapCount; i++) {
      final t = (i + 1) / (strapCount + 1);
      final sx0 = x + (w * t) - (w * 0.05);
      final sx1 = x + (w * t) + (w * 0.05);
      _drawQuad(
        canvas: canvas,
        a: projection.project(sx0, y + (d * 0.02), z + (loadHeight * 0.05)),
        b: projection.project(sx1, y + (d * 0.02), z + (loadHeight * 0.05)),
        c: projection.project(sx1, y + (d * 0.02), z + (loadHeight * 0.95)),
        d: projection.project(sx0, y + (d * 0.02), z + (loadHeight * 0.95)),
        fill: Colors.white.withValues(alpha: 0.6),
        stroke: Colors.white.withValues(alpha: 0.18),
      );
    }
  }

  void _drawQuad({
    required Canvas canvas,
    required Offset a,
    required Offset b,
    required Offset c,
    required Offset d,
    required Color fill,
    required Color stroke,
  }) {
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = stroke,
    );
  }

  void _drawFloorArrow(
    Canvas canvas,
    _Projection projection, {
    required double x,
    required double y,
    required double size,
  }) {
    final half = size * 0.5;
    final p0 = projection.project(x - half, y, 0.09);
    final p1 = projection.project(x, y - (half * 0.9), 0.09);
    final p2 = projection.project(x + half, y, 0.09);
    final p3 = projection.project(x, y + (half * 0.55), 0.09);
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = Colors.amber.withValues(alpha: 0.38),
    );
  }

  double _heatValue(int row, int column, int rows, int columns) {
    if (!heatmapVisible || heatmapData.isEmpty) {
      return ((row + column) % 5) / 5;
    }
    final index = ((row * columns) + column) % heatmapData.length;
    final entry = heatmapData[index];
    return entry.valueFor(heatmapMetric).clamp(0, 1).toDouble();
  }

  Color _heatColor(double value) {
    final safe = value.clamp(0, 1).toDouble();
    if (safe >= 0.85) {
      return Colors.red.shade700;
    }
    if (safe >= 0.65) {
      return Colors.orange.shade700;
    }
    if (safe >= 0.45) {
      return Colors.amber.shade700;
    }
    return colorScheme.primary.withValues(alpha: 0.88);
  }

  bool _isElringLayoutProfile() {
    final normalizedName = warehouse.name.toLowerCase();
    return warehouse.id == 'schlg_rti3-03' ||
        warehouse.id == 'elringklinger-etzberg14' ||
        normalizedName.contains('elring');
  }

  @override
  bool shouldRepaint(covariant _Warehouse3DPainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme ||
        oldDelegate.warehouse != warehouse ||
        oldDelegate.model != model ||
        oldDelegate.zonesVisible != zonesVisible ||
        oldDelegate.heatmapVisible != heatmapVisible ||
        oldDelegate.heatmapMetric != heatmapMetric ||
        oldDelegate.heatmapData != heatmapData ||
        oldDelegate.cameraDrift != cameraDrift ||
        oldDelegate.cameraYaw != cameraYaw ||
        oldDelegate.cameraPitch != cameraPitch ||
        oldDelegate.cameraForward != cameraForward ||
        oldDelegate.cameraStrafe != cameraStrafe ||
        oldDelegate.cameraLift != cameraLift ||
        oldDelegate.isFirstPersonPov != isFirstPersonPov ||
        oldDelegate.showOperatorAvatar != showOperatorAvatar ||
        oldDelegate.operatorForward != operatorForward ||
        oldDelegate.operatorStrafe != operatorStrafe ||
        oldDelegate.operatorLift != operatorLift ||
        oldDelegate.renderQuality != renderQuality ||
        oldDelegate.isCameraInMotion != isCameraInMotion ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.focusZoneName != focusZoneName ||
        oldDelegate.focusZonePulse != focusZonePulse ||
        oldDelegate.focusRackNumber != focusRackNumber ||
        oldDelegate.focusLevelNumber != focusLevelNumber ||
        oldDelegate.focusSlotNumber != focusSlotNumber ||
        oldDelegate.focusSlotPulse != focusSlotPulse ||
        oldDelegate.selectedRackIndex != selectedRackIndex ||
        oldDelegate.selectedRackPulse != selectedRackPulse ||
        oldDelegate.focusedMarkerId != focusedMarkerId ||
        oldDelegate.inspectionMarkers != inspectionMarkers ||
        oldDelegate.aisleSpread != aisleSpread;
  }

  bool _isProjectedOutsideViewport(
    Offset point,
    Size viewport, {
    required double margin,
  }) {
    return point.dx < -margin ||
        point.dy < -margin ||
        point.dx > viewport.width + margin ||
        point.dy > viewport.height + margin;
  }
}

class _Warehouse3DBase {
  const _Warehouse3DBase({
    required this.length,
    required this.width,
    required this.height,
    required this.rows,
    required this.columns,
    required this.levels,
    required this.zones,
  });

  final double length;
  final double width;
  final double height;
  final int rows;
  final int columns;
  final int levels;
  final List<WarehouseModelZone> zones;
}

class _RackAreaMetrics {
  const _RackAreaMetrics({
    required this.originX,
    required this.originY,
    required this.areaLength,
    required this.areaWidth,
    required this.stepX,
    required this.stepY,
    required this.rackLength,
    required this.rackDepth,
    required this.rackHeight,
  });

  final double originX;
  final double originY;
  final double areaLength;
  final double areaWidth;
  final double stepX;
  final double stepY;
  final double rackLength;
  final double rackDepth;
  final double rackHeight;
}

class _NavigationGeometry {
  const _NavigationGeometry({
    required this.length,
    required this.width,
    required this.rows,
    required this.columns,
    required this.originX,
    required this.originY,
    required this.rackAreaLength,
    required this.rackAreaWidth,
    required this.stepX,
    required this.stepY,
    required this.rackLength,
    required this.rackDepth,
  });

  final double length;
  final double width;
  final int rows;
  final int columns;
  final double originX;
  final double originY;
  final double rackAreaLength;
  final double rackAreaWidth;
  final double stepX;
  final double stepY;
  final double rackLength;
  final double rackDepth;
}

class _HeatmapRackSelection {
  const _HeatmapRackSelection({
    required this.row,
    required this.column,
    required this.rackIndex,
    required this.zoneId,
    required this.zoneName,
    required this.heatValue,
    required this.worldCenter,
  });

  final int row;
  final int column;
  final int rackIndex;
  final String? zoneId;
  final String zoneName;
  final double heatValue;
  final Offset worldCenter;
}

class _CameraPlanePosition {
  const _CameraPlanePosition({
    required this.forward,
    required this.strafe,
  });

  final double forward;
  final double strafe;
}

enum _RackRenderDetail {
  low,
  medium,
  high,
}

class _MiniMapPainter extends CustomPainter {
  const _MiniMapPainter({
    required this.geometry,
    required this.position,
    required this.heading,
    required this.colorScheme,
    required this.route,
    required this.waypoints,
    required this.activeWaypointIndex,
    required this.selectedRackIndex,
    required this.heatmapVisible,
    required this.heatmapMetric,
    required this.heatmapData,
    required this.warehouseHeatmapLayer,
    required this.levelFilter,
    required this.totalLevels,
  });

  final _NavigationGeometry geometry;
  final Offset position;
  final double heading;
  final ColorScheme colorScheme;
  final List<Offset> route;
  final List<Offset> waypoints;
  final int? activeWaypointIndex;
  final int? selectedRackIndex;
  final bool heatmapVisible;
  final ViewerHeatmapMetric heatmapMetric;
  final List<ViewerHeatmapEntry> heatmapData;
  final List<WarehouseHeatmapLayerEntry> warehouseHeatmapLayer;
  final int levelFilter;
  final int totalLevels;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colorScheme.surfaceContainerHigh.withValues(alpha: 0.88),
    );

    final dockTop = size.height * 0.88;
    canvas.drawRect(
      Rect.fromLTWH(0, dockTop, size.width, size.height - dockTop),
      Paint()..color = Colors.amber.withValues(alpha: 0.24),
    );

    final colStep = geometry.columns > 28 ? 2 : 1;
    final rowStep = geometry.rows > 18 ? 2 : 1;
    for (var row = 0; row < geometry.rows; row += rowStep) {
      for (var column = 0; column < geometry.columns; column += colStep) {
        final rackX = geometry.originX +
            column * geometry.stepX +
            ((geometry.stepX - geometry.rackLength) * 0.5);
        final rackY = geometry.originY +
            row * geometry.stepY +
            ((geometry.stepY - geometry.rackDepth) * 0.5);
        final x0 = (rackX / geometry.length) * size.width;
        final y0 = (rackY / geometry.width) * size.height;
        final w = (geometry.rackLength / geometry.length) * size.width;
        final h = (geometry.rackDepth / geometry.width) * size.height;
        final rawRackIndex = (row * geometry.columns) + column;
        final rackIndex = rawRackIndex %
            (heatmapData.isEmpty ? 1 : heatmapData.length);
        final heatValue = heatmapData.isEmpty
            ? 0.2
            : heatmapData[rackIndex].valueFor(heatmapMetric).clamp(0, 1).toDouble();
        final adjustedHeatValue = _adjustHeatForLevel(
          heatValue: heatValue,
          rackIndex: rackIndex,
        );
        final baseColor = heatmapVisible
            ? _heatColor(adjustedHeatValue).withValues(alpha: 0.56)
            : colorScheme.outline.withValues(alpha: 0.25);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x0, y0, w, h),
            const Radius.circular(2),
          ),
          Paint()..color = baseColor,
        );
        if (heatmapVisible) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x0, y0, w, h),
              const Radius.circular(2),
            ),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8
              ..color = Colors.white.withValues(alpha: 0.38),
          );
        }
        if (selectedRackIndex != null && selectedRackIndex == rawRackIndex) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x0, y0, w, h),
              const Radius.circular(3),
            ),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = colorScheme.primary.withValues(alpha: 0.92),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x0 - 1.5, y0 - 1.5, w + 3, h + 3),
              const Radius.circular(4),
            ),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = Colors.white.withValues(alpha: 0.86),
          );
        }
      }
    }

    if (heatmapVisible && warehouseHeatmapLayer.isNotEmpty) {
      final csvByRackIndex = _aggregateCsvHeatByRackIndex();
      for (var row = 0; row < geometry.rows; row += rowStep) {
        for (var column = 0; column < geometry.columns; column += colStep) {
          final rawRackIndex = (row * geometry.columns) + column;
          final csvHeat = csvByRackIndex[rawRackIndex];
          if (csvHeat == null) {
            continue;
          }
          final rackX = geometry.originX +
              column * geometry.stepX +
              ((geometry.stepX - geometry.rackLength) * 0.5);
          final rackY = geometry.originY +
              row * geometry.stepY +
              ((geometry.stepY - geometry.rackDepth) * 0.5);
          final x0 = (rackX / geometry.length) * size.width;
          final y0 = (rackY / geometry.width) * size.height;
          final w = (geometry.rackLength / geometry.length) * size.width;
          final h = (geometry.rackDepth / geometry.width) * size.height;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x0, y0, w, h),
              const Radius.circular(2),
            ),
            Paint()..color = _heatColor(csvHeat).withValues(alpha: 0.34),
          );
        }
      }
    }

    if (route.length > 1) {
      final routePath = Path();
      for (var i = 0; i < route.length; i++) {
        final point = route[i];
        final x = (point.dx / geometry.length) * size.width;
        final y = (point.dy / geometry.width) * size.height;
        if (i == 0) {
          routePath.moveTo(x, y);
        } else {
          routePath.lineTo(x, y);
        }
      }
      canvas.drawPath(
        routePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = colorScheme.primary.withValues(alpha: 0.42),
      );
    }

    if (waypoints.isNotEmpty) {
      for (var i = 0; i < waypoints.length; i++) {
        final point = waypoints[i];
        final x = (point.dx / geometry.length) * size.width;
        final y = (point.dy / geometry.width) * size.height;
        final isActive = activeWaypointIndex != null &&
            activeWaypointIndex! >= 0 &&
            activeWaypointIndex!.clamp(0, waypoints.length - 1) == i;
        canvas.drawCircle(
          Offset(x, y),
          isActive ? 5.8 : 4.6,
          Paint()
            ..color = isActive
                ? Colors.deepOrange.withValues(alpha: 0.95)
                : colorScheme.secondary.withValues(alpha: 0.9),
        );
        canvas.drawCircle(
          Offset(x, y),
          isActive ? 8.0 : 6.6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isActive ? 1.8 : 1.3
            ..color = Colors.white.withValues(alpha: 0.75),
        );
      }
    }

    final px = (position.dx / geometry.length) * size.width;
    final py = (position.dy / geometry.width) * size.height;
    final headingVector = Offset(math.sin(heading), math.cos(heading));
    final nose = Offset(px + (headingVector.dx * 12), py + (headingVector.dy * 12));
    final left = Offset(
      px + (math.sin(heading - 2.35) * 7.5),
      py + (math.cos(heading - 2.35) * 7.5),
    );
    final right = Offset(
      px + (math.sin(heading + 2.35) * 7.5),
      py + (math.cos(heading + 2.35) * 7.5),
    );
    final arrow = Path()
      ..moveTo(nose.dx, nose.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()..color = colorScheme.primary.withValues(alpha: 0.92),
    );
    canvas.drawCircle(
      Offset(px, py),
      4,
      Paint()..color = colorScheme.primary,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        oldDelegate.position != position ||
        oldDelegate.heading != heading ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.route != route ||
        oldDelegate.waypoints != waypoints ||
        oldDelegate.activeWaypointIndex != activeWaypointIndex ||
        oldDelegate.selectedRackIndex != selectedRackIndex ||
        oldDelegate.heatmapVisible != heatmapVisible ||
        oldDelegate.heatmapMetric != heatmapMetric ||
        oldDelegate.heatmapData != heatmapData ||
        oldDelegate.warehouseHeatmapLayer != warehouseHeatmapLayer ||
        oldDelegate.levelFilter != levelFilter ||
        oldDelegate.totalLevels != totalLevels;
  }

  Map<int, double> _aggregateCsvHeatByRackIndex() {
    final totalRackCount = (geometry.rows * geometry.columns).clamp(1, 1000000);
    final sumByRack = <int, double>{};
    final countByRack = <int, int>{};
    for (final entry in warehouseHeatmapLayer) {
      if (entry.regal <= 0) {
        continue;
      }
      final rackIndex = (entry.regal - 1) % totalRackCount;
      sumByRack[rackIndex] = (sumByRack[rackIndex] ?? 0) + entry.utilizationUnit;
      countByRack[rackIndex] = (countByRack[rackIndex] ?? 0) + 1;
    }
    final result = <int, double>{};
    for (final entry in sumByRack.entries) {
      final count = countByRack[entry.key] ?? 1;
      result[entry.key] = (entry.value / count).clamp(0, 1).toDouble();
    }
    return result;
  }

  Color _heatColor(double value) {
    final safe = value.clamp(0, 1).toDouble();
    if (safe >= 0.85) {
      return Colors.red.shade700;
    }
    if (safe >= 0.65) {
      return Colors.orange.shade700;
    }
    if (safe >= 0.45) {
      return Colors.amber.shade700;
    }
    return Colors.green.shade700;
  }

  double _adjustHeatForLevel({
    required double heatValue,
    required int rackIndex,
  }) {
    if (levelFilter < 0 || totalLevels <= 1) {
      return heatValue.clamp(0, 1).toDouble();
    }
    final safeLevel = levelFilter.clamp(0, totalLevels - 1);
    final normalizedLevel = safeLevel / (totalLevels - 1);
    final levelBias = (1.06 - (normalizedLevel * 0.18)).clamp(0.78, 1.08);
    final rackVariation = (((rackIndex + (safeLevel * 3)) % 9) / 8)
        .clamp(0.0, 1.0)
        .toDouble();
    final variationFactor = 0.88 + (rackVariation * 0.22);
    return (heatValue * levelBias * variationFactor).clamp(0, 1).toDouble();
  }
}

class _MapLegendBadge extends StatelessWidget {
  const _MapLegendBadge({
    required this.color,
    required this.text,
  });

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 4,
        ),
        backgroundColor:
            active ? colorScheme.primary.withValues(alpha: 0.14) : null,
        side: BorderSide(
          color: active ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      child: Text(label),
    );
  }
}

class _ReviewChip extends StatelessWidget {
  const _ReviewChip({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 6,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _Projection {
  _Projection({
    required this.base,
    required this.size,
    required this.cameraDrift,
    required this.cameraYaw,
    required this.cameraPitch,
    required this.cameraForward,
    required this.cameraStrafe,
    required this.cameraLift,
    required this.isFirstPersonPov,
  }) {
    final sum = (base.length + base.width).clamp(20.0, 240.0);
    final scaleFromWidth = size.width / sum;
    final scaleFromHeight = size.height /
        ((sum * (isFirstPersonPov ? 0.44 : 0.60)) +
            (base.height * (isFirstPersonPov ? 1.35 : 1.1)));
    final cinematicZoom = isFirstPersonPov ? 1.62 : 1.26;
    scale = (math.min(scaleFromWidth, scaleFromHeight) * 0.92 * cinematicZoom)
        .clamp(2.6, 40);

    final halfLength = base.length * 0.5;
    final halfWidth = base.width * 0.5;
    final testPoints = <Offset>[
      _projectRaw(-halfLength, -halfWidth, 0),
      _projectRaw(halfLength, -halfWidth, 0),
      _projectRaw(halfLength, halfWidth, 0),
      _projectRaw(-halfLength, halfWidth, 0),
      _projectRaw(-halfLength, -halfWidth, base.height),
      _projectRaw(halfLength, -halfWidth, base.height),
      _projectRaw(halfLength, halfWidth, base.height),
      _projectRaw(-halfLength, halfWidth, base.height),
    ];

    var minX = testPoints.first.dx;
    var maxX = testPoints.first.dx;
    var minY = testPoints.first.dy;
    var maxY = testPoints.first.dy;
    for (final point in testPoints.skip(1)) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }

    final modelCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final targetCenter = Offset(
      size.width * (0.5 + cameraDrift * 0.03),
      size.height *
          ((isFirstPersonPov ? 0.82 : 0.60) -
              (cameraPitch * (isFirstPersonPov ? 0.10 : 0.035)) -
              (cameraLift * (isFirstPersonPov ? 0.07 : 0.04))),
    );
    center = targetCenter - modelCenter;
  }

  final _Warehouse3DBase base;
  final Size size;
  final double cameraDrift;
  final double cameraYaw;
  final double cameraPitch;
  final double cameraForward;
  final double cameraStrafe;
  final double cameraLift;
  final bool isFirstPersonPov;
  late final double scale;
  late final Offset center;

  Offset project(double x, double y, double z) {
    final centeredX = x - (base.length * 0.5);
    final centeredY = y - (base.width * 0.5);
    final raw = _projectRaw(centeredX, centeredY, z);
    return center + raw;
  }

  Offset _projectRaw(double x, double y, double z) {
    final movedX = x - (cameraStrafe * base.length * 0.36);
    final movedY = y - (cameraForward * base.width * 0.56);
    final movedZ = z -
        (isFirstPersonPov ? 0.0 : (cameraForward * base.height * 0.12)) -
        (cameraLift * base.height * 0.72);

    final yawCos = math.cos(cameraYaw);
    final yawSin = math.sin(cameraYaw);
    final rotatedX = (movedX * yawCos) - (movedY * yawSin);
    final rotatedY = (movedX * yawSin) + (movedY * yawCos);

    final isoCos = isFirstPersonPov ? 0.965 : 0.8660254;
    final isoSin = isFirstPersonPov ? 0.16 : 0.5;
    final verticalFactor = isFirstPersonPov
        ? (1.45 + (cameraPitch * 0.95)).clamp(0.92, 2.1)
        : (0.9 + (cameraPitch * 0.55)).clamp(0.62, 1.28);

    final sx = (rotatedX - rotatedY) * isoCos * scale;
    final sy =
        ((rotatedX + rotatedY) * isoSin * scale) - (movedZ * scale * verticalFactor);
    return Offset(sx, sy);
  }
}

enum _JoystickAxis {
  free,
  vertical,
}

class _VirtualJoystick extends StatefulWidget {
  const _VirtualJoystick({
    required this.icon,
    required this.label,
    required this.onChanged,
    this.axis = _JoystickAxis.free,
  });

  final IconData icon;
  final String label;
  final ValueChanged<Offset> onChanged;
  final _JoystickAxis axis;

  @override
  State<_VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<_VirtualJoystick> {
  static const double _size = 118;
  static const double _thumbSize = 40;
  Offset _value = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = (_size - _thumbSize) / 2;
    final thumbCenter = Offset(
      (_size / 2) + (_value.dx * radius),
      (_size / 2) + (_value.dy * radius),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          widget.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        GestureDetector(
          onPanStart: (details) => _update(details.localPosition),
          onPanUpdate: (details) => _update(details.localPosition),
          onPanEnd: (_) => _reset(),
          onPanCancel: _reset,
          child: SizedBox(
            width: _size,
            height: _size,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.surface.withValues(alpha: 0.58),
                      border: Border.all(
                        color: colorScheme.onSurface.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 20,
                      color: colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                Positioned(
                  left: thumbCenter.dx - (_thumbSize / 2),
                  top: thumbCenter.dy - (_thumbSize / 2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary.withValues(alpha: 0.92),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: _thumbSize,
                      height: _thumbSize,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _update(Offset localPosition) {
    const center = Offset(_size / 2, _size / 2);
    final delta = localPosition - center;
    final maxDistance = (_size - _thumbSize) / 2;
    final distance = delta.distance;
    final limited = distance > maxDistance && distance > 0
        ? (delta / distance) * maxDistance
        : delta;
    final normalized = switch (widget.axis) {
      _JoystickAxis.free => Offset(
          (limited.dx / maxDistance).clamp(-1, 1).toDouble(),
          (limited.dy / maxDistance).clamp(-1, 1).toDouble(),
        ),
      _JoystickAxis.vertical => Offset(
          0,
          (limited.dy / maxDistance).clamp(-1, 1).toDouble(),
        ),
    };
    final curved = _applyDeadzoneAndCurve(normalized);
    setState(() => _value = curved);
    widget.onChanged(curved);
  }

  Offset _applyDeadzoneAndCurve(Offset input) {
    double shape(double value) {
      const deadzone = 0.10;
      final abs = value.abs();
      if (abs <= deadzone) {
        return 0;
      }
      final normalized = ((abs - deadzone) / (1 - deadzone))
          .clamp(0.0, 1.0)
          .toDouble();
      final curved = (normalized * normalized * (3 - (2 * normalized)))
          .clamp(0.0, 1.0)
          .toDouble();
      return value.isNegative ? -curved : curved;
    }

    return Offset(
      shape(input.dx),
      shape(input.dy),
    );
  }

  void _reset() {
    setState(() => _value = Offset.zero);
    widget.onChanged(Offset.zero);
  }
}

