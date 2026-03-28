precision highp float;
varying vec2 v_texcoord;
uniform sampler2D tex;

void main() {
    vec2 uv = v_texcoord;
    float r = 0.003933;

    // Full-screen smooth two-ring weighted blur.
    vec4 blur = texture2D(tex, uv) * 0.16;

    blur += texture2D(tex, uv + vec2( r, 0.0)) * 0.10;
    blur += texture2D(tex, uv + vec2(-r, 0.0)) * 0.10;
    blur += texture2D(tex, uv + vec2(0.0,  r)) * 0.10;
    blur += texture2D(tex, uv + vec2(0.0, -r)) * 0.10;

    blur += texture2D(tex, uv + vec2( r,  r)) * 0.075;
    blur += texture2D(tex, uv + vec2(-r,  r)) * 0.075;
    blur += texture2D(tex, uv + vec2( r, -r)) * 0.075;
    blur += texture2D(tex, uv + vec2(-r, -r)) * 0.075;

    float r2 = r * 2.0;
    blur += texture2D(tex, uv + vec2( r2, 0.0)) * 0.03;
    blur += texture2D(tex, uv + vec2(-r2, 0.0)) * 0.03;
    blur += texture2D(tex, uv + vec2(0.0,  r2)) * 0.03;
    blur += texture2D(tex, uv + vec2(0.0, -r2)) * 0.03;

    blur += texture2D(tex, uv + vec2( r2,  r2)) * 0.005;
    blur += texture2D(tex, uv + vec2(-r2,  r2)) * 0.005;
    blur += texture2D(tex, uv + vec2( r2, -r2)) * 0.005;
    blur += texture2D(tex, uv + vec2(-r2, -r2)) * 0.005;

    gl_FragColor = blur;
}
