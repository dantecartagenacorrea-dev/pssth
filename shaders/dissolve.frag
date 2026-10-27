#version 460 core
// Máscara de desintegración: la pantalla se parte en celdas que aparecen (o se
// van) en desorden, con un leve barrido de arriba abajo.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uProgress;
uniform float uCell;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 cell = floor(p / uCell);
  float v = hash(cell) * 0.75 + clamp(p.y / uSize.y, 0.0, 1.0) * 0.25;
  float a = step(v, uProgress * 1.02);
  fragColor = vec4(a);
}
