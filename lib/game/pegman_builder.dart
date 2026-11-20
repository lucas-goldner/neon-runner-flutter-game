import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'neon_palette.dart';

/// Procedural 3D Street View Pegman built from Flutter Scene primitives,
/// complete with animated limbs, sky-drop vertical plasma beam, and trailing
/// neon ribbon segments + spark particles.
class PegmanRig {
  PegmanRig() {
    _buildPegman();
    _buildTrail();
    _buildSparks();
  }

  final fs.Node root = fs.Node(name: 'pegman_root');
  final fs.Node bodyPivot = fs.Node(name: 'pegman_body_pivot');
  late final fs.Node leftArm;
  late final fs.Node rightArm;
  late final fs.Node leftLeg;
  late final fs.Node rightLeg;
  late final fs.Node skyBeam;

  final List<fs.Node> trailSegments = [];
  final List<vm.Vector3> _trailHistory = [];
  final List<fs.Node> sparkNodes = [];

  static const int trailCount = 22;
  static const int sparkCount = 12;

  double _runCycle = 0.0;

  void _buildPegman() {
    final pegmanMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = NeonPalette.pegmanBase
      ..metallicFactor = 0.08
      ..roughnessFactor = 0.28
      ..emissiveFactor = NeonPalette.emissivePegman;

    // Iconic round Pegman head
    final head = fs.Node(
      name: 'pegman_head',
      mesh: fs.Mesh(fs.SphereGeometry(radius: 0.34), pegmanMat),
    )..position = vm.Vector3(0, 1.56, 0);

    // Chunky rounded-silhouette torso
    final torso = fs.Node(
      name: 'pegman_torso',
      mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.62, 0.70, 0.36)), pegmanMat),
    )..position = vm.Vector3(0, 0.96, 0);

    // Arms
    leftArm = fs.Node(
      name: 'pegman_left_arm',
      mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.20, 0.62, 0.22)), pegmanMat),
    )..position = vm.Vector3(-0.44, 0.96, 0);

    rightArm = fs.Node(
      name: 'pegman_right_arm',
      mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.20, 0.62, 0.22)), pegmanMat),
    )..position = vm.Vector3(0.44, 0.96, 0);

    // Legs
    leftLeg = fs.Node(
      name: 'pegman_left_leg',
      mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.24, 0.62, 0.26)), pegmanMat),
    )..position = vm.Vector3(-0.17, 0.32, 0);

    rightLeg = fs.Node(
      name: 'pegman_right_leg',
      mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.24, 0.62, 0.26)), pegmanMat),
    )..position = vm.Vector3(0.17, 0.32, 0);

    // Vertical plasma drop beam visible during SKY DROP
    final beamMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.35, 0.25, 0.85)
      ..metallicFactor = 0.0
      ..roughnessFactor = 1.0
      ..alphaMode = fs.AlphaMode.blend
      ..emissiveFactor = vm.Vector4(3.2, 0.45, 0.35, 1.0);

    skyBeam = fs.Node(
      name: 'sky_drop_beam',
      mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.32, 26.0, 0.32)), beamMat),
    )..position = vm.Vector3(0, 14.5, 0);

    bodyPivot.addAll([head, torso, leftArm, rightArm, leftLeg, rightLeg]);
    root.addAll([bodyPivot, skyBeam]);
  }

  void _buildTrail() {
    for (int i = 0; i < trailCount; i++) {
      final t = i / trailCount;
      // Blend from bright warm white-pink near Pegman to magenta-orange tail
      final mat = fs.PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(1.0, 0.55 - t * 0.35, 0.78 - t * 0.3, 0.85 * (1.0 - t))
        ..metallicFactor = 0.0
        ..roughnessFactor = 1.0
        ..alphaMode = fs.AlphaMode.blend
        ..emissiveFactor = vm.Vector4(
          3.0 * (1.0 - t * 0.55),
          (1.2 - t * 0.9).clamp(0.15, 2.0),
          (2.2 - t * 1.1).clamp(0.2, 2.6),
          1.0,
        );

      final width = (0.34 * (1.0 - t * 0.65)).clamp(0.08, 0.4);
      final node = fs.Node(
        name: 'trail_$i',
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(width, 0.08, 0.95)), mat),
      )..visible = false;
      trailSegments.add(node);
    }
  }

  void _buildSparks() {
    final sparkMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.92, 0.45, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.5
      ..emissiveFactor = vm.Vector4(3.6, 2.4, 0.55, 1.0);

    for (int i = 0; i < sparkCount; i++) {
      final node = fs.Node(
        name: 'spark_$i',
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.08, 0.08, 0.45)), sparkMat),
      )..visible = false;
      sparkNodes.add(node);
    }
  }

  void attachToScene(fs.Scene scene) {
    scene.add(root);
    scene.addAll(trailSegments);
    scene.addAll(sparkNodes);
  }

  void resetTrail(vm.Vector3 startPos) {
    _trailHistory
      ..clear()
      ..addAll(List.generate(trailCount, (_) => startPos.clone()));
    for (final seg in trailSegments) {
      seg.visible = false;
    }
    for (final s in sparkNodes) {
      s.visible = false;
    }
  }

  void updatePose({
    required double dt,
    required vm.Vector3 worldPosition,
    required double laneVelocityX,
    required bool isSkyDrop,
    required bool isSliding,
    required bool isJumping,
    required bool isGrinding,
    required bool isWallRunning,
    required bool isVictory,
    required double wallSide,
    required double speedRatio,
    required double time,
  }) {
    root.position = worldPosition;
    skyBeam.visible = isSkyDrop;

    // Record ribbon trail
    if (_trailHistory.isEmpty) {
      resetTrail(worldPosition);
    }
    _trailHistory.insert(0, worldPosition + vm.Vector3(0, isSkyDrop ? 0.8 : 0.25, 0.35));
    if (_trailHistory.length > trailCount) {
      _trailHistory.removeLast();
    }

    for (int i = 0; i < trailSegments.length; i++) {
      final seg = trailSegments[i];
      if (isVictory || i >= _trailHistory.length - 1) {
        seg.visible = false;
        continue;
      }
      seg.visible = true;
      final p0 = _trailHistory[i];
      final p1 = _trailHistory[i + 1];
      seg.position = (p0 + p1) * 0.5;
      final dx = p0.x - p1.x;
      final dz = p0.z - p1.z;
      final yaw = math.atan2(dx, dz == 0 ? -0.001 : dz);
      seg.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);
    }

    // Sparks during rail grind, wall run, or boost
    final showSparks = !isVictory && (isGrinding || isWallRunning);
    for (int i = 0; i < sparkNodes.length; i++) {
      final spark = sparkNodes[i];
      spark.visible = showSparks;
      if (!showSparks) continue;
      final phase = (time * 8.0 + i * 0.53) % 1.0;
      final spreadX = math.sin(i * 2.1 + time * 14.0) * (0.3 + phase * 1.1);
      final spreadY = (0.1 + phase * 1.2) - phase * phase * 0.9;
      spark.position = worldPosition +
          vm.Vector3(
            spreadX + (isWallRunning ? -wallSide * 0.45 : 0.0),
            spreadY.clamp(0.05, 1.5),
            0.4 + phase * 2.6,
          );
      spark.rotation = vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, 0),
        spreadX * 0.6,
      );
    }

    // Body pose animations
    if (isVictory) {
      final bounce = (math.sin(time * 6.5).abs()) * 0.25;
      bodyPivot.position = vm.Vector3(0, bounce, 0);
      bodyPivot.scale = vm.Vector3.all(1.0);
      bodyPivot.rotation = vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, 0),
        math.pi + math.sin(time * 2.2) * 0.35,
      );
      leftArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -2.4 + math.sin(time * 8) * 0.35);
      rightArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), 2.4 - math.sin(time * 8) * 0.35);
      leftLeg.rotation = vm.Quaternion.identity();
      rightLeg.rotation = vm.Quaternion.identity();
      return;
    }

    if (isSkyDrop) {
      // Classic star-pose descending into Shibuya
      bodyPivot.position = vm.Vector3(0, 0, 0);
      bodyPivot.scale = vm.Vector3.all(1.0);
      bodyPivot.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.sin(time * 3.0) * 0.12);
      leftArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -1.15);
      rightArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), 1.15);
      leftLeg.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -0.22);
      rightLeg.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), 0.22);
      return;
    }

    _runCycle += dt * (11.0 + speedRatio * 9.0);
    final bankRoll = (-laneVelocityX * 0.045).clamp(-0.35, 0.35) +
        (isWallRunning ? wallSide * 0.52 : 0.0);

    if (isSliding) {
      bodyPivot.position = vm.Vector3(0, -0.34, 0);
      bodyPivot.scale = vm.Vector3(1.05, 0.56, 1.15);
      bodyPivot.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -0.65);
      leftArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -0.8);
      rightArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), 0.8);
      leftLeg.rotation = vm.Quaternion.identity();
      rightLeg.rotation = vm.Quaternion.identity();
    } else if (isGrinding) {
      bodyPivot.position = vm.Vector3(0, 0.06, 0);
      bodyPivot.scale = vm.Vector3.all(1.0);
      bodyPivot.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.35) *
          vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), bankRoll + math.sin(time * 9) * 0.08);
      leftArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -1.25);
      rightArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), 1.25);
      leftLeg.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.25);
      rightLeg.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -0.25);
    } else if (isJumping) {
      bodyPivot.position = vm.Vector3(0, 0.05, 0);
      bodyPivot.scale = vm.Vector3.all(1.0);
      bodyPivot.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.22) *
          vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), bankRoll);
      leftArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -1.1);
      rightArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -1.1);
      leftLeg.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.65);
      rightLeg.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -0.45);
    } else {
      final stride = math.sin(_runCycle);
      final bob = stride.abs() * 0.10;
      bodyPivot.position = vm.Vector3(0, bob, 0);
      bodyPivot.scale = vm.Vector3.all(1.0);
      bodyPivot.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.16) *
          vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), bankRoll);
      leftArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -stride * 0.9);
      rightArm.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), stride * 0.9);
      leftLeg.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), stride * 0.95);
      rightLeg.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -stride * 0.95);
    }
  }
}
