#version 440
// The whole bar silhouette as a signed distance field: a rounded bar whose top and bottom edges are smooth harmonic waves (a sum of sines under a bell-shaped
// attenuation envelope, the classic "Siri wave"), compressed in height to make room for them so nothing leaves the bar's box. Anti-aliased analytically.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 dims;       // the bar's size in px
    float radius;    // its corner radius
    float squeeze;   // how far the top edge gives way to its waves (px); 0 at rest
    float reachB;    // how far the bottom waves reach below the bar (px); 0 at rest
    float time;      // wave phase
    float tint;      // how much of the palette the body takes
    float rimMix;    // lighter rim inside the edge while active
    float borderMix; // the bar's own 1px border (resting look)
    float drift;     // palette flows along the bar
    float extraMax;  // px the item extends below the bar (room the shape may grow into while active)
    float style;     // 0 siri, 1 liquid, 2 bars, 3 aurora, 4 ripple, 5 calm
    vec4 bg;         // premultiplied
    vec4 border;     // premultiplied
    vec4 p0; vec4 p1; vec4 p2; vec4 p3;  // palette, cyclic
    float b0; float b1; float b2; float b3; float b4; float b5; float b6; float b7;
    float b8; float b9; float b10; float b11; float b12; float b13; float b14; float b15;  // energy across the bar, left to right
} ubuf;

float envelope(float u) {  // 1 in the middle, soft towards the ends (SiriWave attenuation, K = 4)
    float x = (2.0 * u - 1.0) * 1.35;
    return pow(4.0 / (4.0 + pow(abs(x), 4.0)), 4.0);
}

float band(int i) {  // no arrays: this has to compile for old GLSL targets too
    if (i <= 0) return ubuf.b0;
    if (i == 1) return ubuf.b1;
    if (i == 2) return ubuf.b2;
    if (i == 3) return ubuf.b3;
    if (i == 4) return ubuf.b4;
    if (i == 5) return ubuf.b5;
    if (i == 6) return ubuf.b6;
    if (i == 7) return ubuf.b7;
    if (i == 8) return ubuf.b8;
    if (i == 9) return ubuf.b9;
    if (i == 10) return ubuf.b10;
    if (i == 11) return ubuf.b11;
    if (i == 12) return ubuf.b12;
    if (i == 13) return ubuf.b13;
    if (i == 14) return ubuf.b14;
    return ubuf.b15;
}

float energy(float u) {  // smooth interpolation of the 16 band values
    float v = clamp(u, 0.0, 1.0) * 15.0;
    int i = int(floor(v));
    float f = v - float(i);
    f = f * f * (3.0 - 2.0 * f);
    return mix(band(i), band(i + 1), f);
}

float avgEnergy() { return (ubuf.b0 + ubuf.b1 + ubuf.b2 + ubuf.b3 + ubuf.b4 + ubuf.b5 + ubuf.b6 + ubuf.b7 + ubuf.b8 + ubuf.b9 + ubuf.b10 + ubuf.b11 + ubuf.b12 + ubuf.b13 + ubuf.b14 + ubuf.b15) * 0.0625; }

float blob(float x, float c, float w, float k) {  // one soft drop of liquid
    float g = exp(-pow((x - c) / w, 2.0));
    return g * (0.3 + 0.7 * energy(c / ubuf.dims.x)) * k;
}

float wave(float x, float ph) {  // 0..1 height of the wave at x
    float u = x / ubuf.dims.x, t = ubuf.time;
    float s = 0.50 * (0.5 + 0.5 * sin(6.2831853 * x / 260.0 - t * 1.7 + ph))
            + 0.33 * (0.5 + 0.5 * sin(6.2831853 * x / 410.0 + t * 1.1 + ph * 1.7 + 1.3))
            + 0.17 * (0.5 + 0.5 * sin(6.2831853 * x / 150.0 - t * 2.6 + ph * 0.6 + 2.1));
    return clamp(s * envelope(u) * energy(u), 0.0, 1.0);
}

// How far the edge rises at x (0..1) for the smooth styles.
float edgeH(float x, float ph) {
    float s = ubuf.style, W = ubuf.dims.x, t = ubuf.time;
    if (s < 0.5) return wave(x, ph);                                  // siri: layered sines
    if (s < 1.5) {                                                    // liquid: a few drops that drift and merge
        float a = blob(x, W * (0.5 + 0.36 * sin(t * 0.35 + ph * 0.8)), 200.0, 1.2);
        float b = blob(x, W * (0.5 + 0.36 * sin(t * 0.52 + ph * 0.8 + 2.1)), 150.0, 1.1);
        float c = blob(x, W * (0.5 + 0.36 * sin(t * 0.29 + ph * 0.8 + 4.2)), 260.0, 1.0);
        return clamp(1.0 - (1.0 - clamp(a, 0.0, 1.0)) * (1.0 - clamp(b, 0.0, 1.0)) * (1.0 - clamp(c, 0.0, 1.0)), 0.0, 1.0);
    }
    if (s < 3.5) return 0.4 * wave(x, ph);                            // aurora: only a gentle swell, the light does the talking
    if (s < 4.5) {                                                    // ripple: the sound itself spreading out from the middle; each loud moment becomes a ring that travels outwards
        return clamp(energy(x / W) * (0.65 + 0.35 * envelope(x / W)) * 1.15, 0.0, 1.0);
    }
    return clamp(avgEnergy() * 1.4 * (0.55 + 0.45 * sin(t * 1.4)), 0.0, 1.0);  // calm: the whole bar just breathes
}

float smin(float a, float b, float k) {  // smooth union: where two shapes meet they flow together with a neck
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// liquid: drops of the bar's own material that bulge out of its edges, slide along and merge into it
float drops(vec2 p, float base, float T, float B) {
    float W = ubuf.dims.x, t = ubuf.time, d = base, k = 15.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float cx = W * (0.5 + 0.44 * sin(t * (0.30 + 0.07 * fi) + fi * 1.9));
        float e = 0.55 + 0.45 * energy(cx / W);
        float R = ubuf.reachB * e * (0.9 + 0.1 * sin(t * 2.0 + fi * 1.7));
        d = smin(d, length(p - vec2(cx, B - 1.0)) - R, k);                      // hangs below
        float cx2 = W * (0.5 + 0.44 * sin(t * (0.26 + 0.08 * fi) + fi * 1.9 + 3.1));
        float R2 = ubuf.squeeze * (0.55 + 0.45 * energy(cx2 / W)) * (0.9 + 0.1 * sin(t * 2.3 + fi));
        d = smin(d, length(p - vec2(cx2, T + 1.0)) - R2, k);                    // rises above
    }
    return d;
}

float capsule(vec2 p, float a, float b, float r) {  // distance to a vertical capsule from y=a down/up to y=b
    float t = clamp((p.y - a) / (b - a + 0.0001), 0.0, 1.0);
    return length(p - vec2(0.0, a + (b - a) * t)) - r;
}

vec3 swatch(int i) {
    if (i <= 0) return ubuf.p0.rgb;
    if (i == 1) return ubuf.p1.rgb;
    if (i == 2) return ubuf.p2.rgb;
    return ubuf.p3.rgb;
}

vec3 palette(float t) {
    t = fract(t) * 4.0;
    int i = int(floor(t));
    float f = t - float(i);
    f = f * f * (3.0 - 2.0 * f);
    return mix(swatch(i), swatch(i >= 3 ? 0 : i + 1), f);
}

void main() {
    vec2 p = qt_TexCoord0 * ubuf.dims;
    float T = ubuf.squeeze;                       // top edge: gives way a little, the top waves rise into the space it frees
    float B = ubuf.dims.y - ubuf.extraMax;        // bottom edge: always the bar's own bottom; the bottom waves hang into the free space below
    float cy = (T + B) * 0.5, hh = (B - T) * 0.5;
    bool top = p.y < cy;
    float ph = top ? 0.0 : 1.7;
    float amp = top ? ubuf.squeeze : ubuf.reachB;
    float r = clamp(min(ubuf.radius, hh), 0.0, hh);
    float sd;
    if (ubuf.style > 0.5 && ubuf.style < 1.5) {
        vec2 q0 = abs(vec2(p.x - ubuf.dims.x * 0.5, p.y - cy)) - vec2(ubuf.dims.x * 0.5, hh) + r;
        float base = length(max(q0, 0.0)) + min(max(q0.x, q0.y), 0.0) - r;
        sd = drops(p, base, T, B);
    } else if (ubuf.style > 1.5 && ubuf.style < 2.5) {
        // bars: soft rounded capsules standing on the bar
        vec2 q0 = abs(vec2(p.x - ubuf.dims.x * 0.5, p.y - cy)) - vec2(ubuf.dims.x * 0.5, hh) + r;
        float base = length(max(q0, 0.0)) + min(max(q0.x, q0.y), 0.0) - r;
        float pitch = 24.0, rr = 8.0;
        float cell = floor(p.x / pitch), cx = (cell + 0.5) * pitch;
        float u = cx / ubuf.dims.x;
        float n = 0.5 + 0.5 * sin(cell * 12.9898 + ubuf.time * (2.0 + fract(cell * 0.37) * 2.5) + ph);
        float hb = amp * clamp(energy(u) * (0.3 + 0.7 * n) * (0.45 + 0.55 * envelope(u)), 0.0, 1.0);
        float rad = min(rr, hb * 0.5 + 0.01);
        float y = top ? p.y : 2.0 * cy - p.y;  // mirrored: the same capsule on both edges
        float dcap = capsule(vec2(p.x - cx, y), T + 1.0, T - hb + rad, rad);
        sd = min(base, dcap);
    } else {
        float h = amp * edgeH(p.x, ph);
        float slope = (amp * edgeH(p.x + 2.0, ph) - h) / 2.0;
        float yy = top ? p.y + h : p.y - h;  // the edge moves out by h: look the point up in the box
        vec2 q = abs(vec2(p.x - ubuf.dims.x * 0.5, yy - cy)) - vec2(ubuf.dims.x * 0.5, hh) + r;
        sd = (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r) * inversesqrt(1.0 + slope * slope);  // px, negative inside
    }
    float aa = 1.0 - smoothstep(-0.75, 0.75, sd);

    vec3 pal = palette(p.x / ubuf.dims.x * 0.8 + ubuf.drift);
    vec4 c = vec4(mix(ubuf.bg.rgb, pal * 0.78 * ubuf.bg.a, ubuf.tint), mix(ubuf.bg.a, 1.0, ubuf.tint));  // active: the whole bar becomes the colour (slightly deepened so the text stays readable)
    float aur = ubuf.style > 2.5 && ubuf.style < 3.5 ? 1.0 : 0.0;
    float rim = ubuf.rimMix * mix(1.0 - smoothstep(0.7, 1.9, -sd), (1.0 - smoothstep(0.0, 16.0, -sd)) * (0.65 + 0.35 * sin(p.x * 0.017 + ubuf.time * 0.9 + p.y * 0.12)), aur);
    c = mix(c, vec4(mix(pal, vec3(1.0), 0.3) * 0.95, 0.95), rim);
    c = mix(c, ubuf.border, ubuf.borderMix * (1.0 - smoothstep(0.4, 1.4, -sd)));
    fragColor = c * aa * ubuf.qt_Opacity;
}
