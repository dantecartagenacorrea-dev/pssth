#version 460 core
// Fondo de puntos en la GPU: malla que ondula como tela e hilos de luz que
// serpentean. Mismo dibujo que el que antes se calculaba punto por punto.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;

out vec4 fragColor;

const float GAP = 14.0;

float wave(vec2 p, float t) {
  return sin(p.x * 0.018 + t * 0.6) * cos(p.y * 0.011 - t * 0.4) + 0.5 * sin((p.x + p.y) * 0.01 + t * 0.9);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  float t = uTime;
  // Malla: cada punto se corre según la onda; se buscan los puntos vecinos
  // que pueden haber caído sobre este pixel.
  float grid = 0.0;
  vec2 base = floor(px / GAP);
  for (int i = -1; i <= 1; i++) {
    for (int j = -2; j <= 2; j++) {
      vec2 cell = (base + vec2(float(i), float(j))) * GAP;
      float h = wave(cell, t);
      vec2 dot = cell + vec2(h * 4.0, h * 16.0);
      float d = length(px - dot);
      float lit = 0.05 + 0.22 * clamp((h + 1.5) / 3.0, 0.0, 1.0);
      grid = max(grid, lit * (1.0 - smoothstep(0.4, 1.3, d)));
    }
  }
  // Hilos de luz punteados.
  float thread = 0.0;
  for (int k = 0; k < 3; k++) {
    float th = float(k);
    float s = px.y / uSize.y;
    s = (px.y - 40.0 * sin(s * 9.0 + t * 0.7 + th)) / uSize.y;
    float x = uSize.x * (0.5 + 0.42 * sin(s * 2.4 + t * 0.25 + th * 2.1));
    float dx = abs(px.x - x);
    // Puntos sueltos y tenues, como el resto del éter.
    float dots = step(0.8, fract(s * 160.0));
    thread = max(thread, 0.14 * dots * (1.0 - smoothstep(0.3, 1.4, dx)));
  }
  float a = max(grid, thread);
  fragColor = vec4(a, a, a, 1.0);
}
