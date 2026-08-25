#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 screenSize;
    vec2 origin;
    float radius;
    float edge;
    float progress;
} ubuf;

void main()
{
    vec2 pos = qt_TexCoord0 * ubuf.screenSize;
    float dist = distance(pos, ubuf.origin);
    float angle = atan(pos.y - ubuf.origin.y, pos.x - ubuf.origin.x);
    float ripple = sin((pos.x * 0.018) + (pos.y * 0.013) + ubuf.progress * 8.0) * 0.16;
    float wave = (sin(angle * 5.0 + ubuf.progress * 4.7)
                + 0.62 * sin(angle * 9.0 - ubuf.progress * 5.3)
                + 0.34 * sin(angle * 15.0 + 1.4)
                + ripple) * ubuf.edge * 0.64;
    float front = ubuf.radius + wave;
    float alpha = 1.0 - smoothstep(front - ubuf.edge, front + ubuf.edge, dist);
    vec4 color = texture(source, qt_TexCoord0);
    fragColor = vec4(color.rgb * alpha, color.a * alpha) * ubuf.qt_Opacity;
}
