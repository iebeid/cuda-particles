#version 410
out vec4 frag_colour;
in vec3 color_in;

void main () {
frag_colour = vec4 (color_in, 1.0);
}