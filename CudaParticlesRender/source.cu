
#include <stdlib.h>
#include <stdio.h>
#include <time.h>

#include <iostream>
#include <cmath>
#include <string>
#include <fstream>
#include <map>
#include <future>

#include <glm/glm.hpp>
#include <glm/vec3.hpp>
#include <glm/vec4.hpp>
#include <glm/mat4x4.hpp>
#include <glm/gtc/matrix_transform.hpp> 
#include <glm/gtc/type_ptr.hpp>

#include <cuda_runtime.h>
#include <device_launch_parameters.h>

#include <GL/glew.h>
#include <GLFW/glfw3.h>

using namespace std;

float y_rotation = 0.0f;
float angle = 0.0f;
int n = 300000;

class v3
{
public:
	float x;
	float y;
	float z;

	v3(){ randomize(); }
	v3(float xIn, float yIn, float zIn) : x(xIn), y(yIn), z(zIn)
	{}
	void randomize(){
		x = (float)rand() / (float)RAND_MAX;
		y = (float)rand() / (float)RAND_MAX;
		z = (float)rand() / (float)RAND_MAX;
	}
	__host__ __device__ void normalize(){
		float t = sqrt(x*x + y*y + z*z);
		x /= t;
		y /= t;
		z /= t;
	}
	__host__ __device__ void scramble(){
		float tx = 0.317f*(x + 1.0) + y + z * x * x + y + z;
		float ty = 0.619f*(y + 1.0) + y * y + x * y * z + y + x;
		float tz = 0.124f*(z + 1.0) + z * y + x * y * z + y + x;

		//float tx = x;
		//float ty = y;
		//float tz = z;


		x = tx;
		y = ty;
		z = tz;
	}

};

class particle
{
public:
	v3 position;
	v3 velocity;
	v3 totalDistance;
	float life;

public:
	particle() : position(), velocity(), totalDistance(0, 0, 0), life()
	{}
	__host__ __device__ void advance(float d){
		velocity.normalize();
		float dx = d * velocity.x * velocity.x;
		position.x += dx;
		totalDistance.x += dx;
		float dy = d * velocity.y * velocity.y;
		position.y += dy;
		totalDistance.y += dy;
		float dz = d * velocity.z * velocity.z;
		position.z += dz;
		totalDistance.z += dz;
		life -= d;
		velocity.scramble();
	}

	const v3& getTotalDistance() const{
		return totalDistance;
	}

};

__global__ void advanceParticles(float dt, particle * pArray, int nParticles)
{
	int idx = threadIdx.x + blockIdx.x*blockDim.x;
	if (idx < nParticles)
	{
		pArray[idx].advance(dt);
	}
}

void controls(GLFWwindow* window, int key, int scancode, int action, int mods)
{
	if (action == GLFW_PRESS)
		if (key == GLFW_KEY_ESCAPE)
			glfwSetWindowShouldClose(window, GL_TRUE);
}

void mouse_button_callback(GLFWwindow* window, int button, int action, int mods)
{
	if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS)
		angle = angle + 0.1f;
}

GLFWwindow* initWindow(const int resX, const int resY)
{
	if (!glfwInit())
	{
		fprintf(stderr, "Failed to initialize GLFW\n");
		return NULL;
	}
	glfwWindowHint(GLFW_SAMPLES, 4);
	GLFWwindow* window = glfwCreateWindow(resX, resY, "Render Cuda Particles", NULL, NULL);
	if (window == NULL)
	{
		fprintf(stderr, "Failed to open GLFW window.\n");
		glfwTerminate();
		return NULL;
	}
	glfwMakeContextCurrent(window);
	glfwSetKeyCallback(window, controls);
	glfwSetMouseButtonCallback(window, mouse_button_callback);
	glewExperimental = GL_TRUE;
	glewInit();
	printf("Renderer: %s\n", glGetString(GL_RENDERER));
	printf("OpenGL version supported %s\n", glGetString(GL_VERSION));
	glEnable(GL_DEPTH_TEST);
	glDepthMask(GL_TRUE);
	glDepthFunc(GL_LEQUAL);
	glCullFace(GL_BACK);
	return window;
}

void display(GLFWwindow* window)
{
	particle * pArray = new particle[n];
	particle * devPArray = NULL;
	cudaMalloc(&devPArray, n*sizeof(particle));
	cudaMemcpy(devPArray, pArray, n*sizeof(particle), cudaMemcpyHostToDevice);

	std::string vertex_line, vertex_text;
	std::ifstream vertex_in("vertex.vert");
	while (std::getline(vertex_in, vertex_line))
	{
		vertex_text += vertex_line + "\n";
	}
	
	std::string frag_line, frag_text;
	std::ifstream frag_in("fragment.frag");
	while (std::getline(frag_in, frag_line))
	{
		frag_text += frag_line + "\n";
	}

	const char* vertex_data = vertex_text.c_str();
	const char* fragment_data = frag_text.c_str();
	const char* vertex_shader = vertex_data;
	const char* fragment_shader = fragment_data;

	GLfloat *colors = new GLfloat[n * 3];
	int j = 0;
	for (int i = 0; i<n; i = i + 3)
	{
		colors[i] = ((float)rand() / (RAND_MAX)) + 1;
		colors[i + 1] = ((float)rand() / (RAND_MAX)) + 1;
		colors[i + 2] = ((float)rand() / (RAND_MAX)) + 1;
	}
	GLfloat *vertices = new GLfloat[n * 3];
	while (!glfwWindowShouldClose(window))
	{
		//Calulations
		float dt = (float)rand() / (float)RAND_MAX;
		advanceParticles <<< 1 + n / 256, 256 >>>(dt, devPArray, n);
		cudaDeviceSynchronize();
		cudaMemcpy(pArray, devPArray, n * sizeof(particle), cudaMemcpyDeviceToHost);
		
		//GLfloat *colors = new GLfloat[n * 3];
		int j = 0;
		for (int i = 0; i<n; i = i + 3)
		{
			v3 pos = pArray[j].position;
			float vertex_magnitude = sqrt(pow(pos.x, 2) + pow(pos.y, 2) + pow(pos.z, 2));
			vertices[i] = pos.x / vertex_magnitude;
			vertices[i + 1] = pos.y / vertex_magnitude;
			vertices[i + 2] = pos.z / vertex_magnitude;

			//colors[i] = ((float)rand() / (RAND_MAX)) + 1;
			//colors[i + 1] = ((float)rand() / (RAND_MAX)) + 1;
			//colors[i + 2] = ((float)rand() / (RAND_MAX)) + 1;
			j++;
		}

		// Scale to window size
		GLint windowWidth, windowHeight;
		glfwGetWindowSize(window, &windowWidth, &windowHeight);
		glViewport(0, 0, windowWidth, windowHeight);

		glClearColor(0.1, 0.1, 0.1, 1.0);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		glMatrixMode(GL_PROJECTION_MATRIX);
		glm::mat4 Projection = glm::perspective(60.0f, (float)windowWidth / (float)windowHeight, 0.1f, 1000.f);

		glMatrixMode(GL_MODELVIEW_MATRIX);

		glRotatef(angle, 0.0f, 1.0f, 0.0f);

		GLuint vboId;
		GLuint cboId;

		glGenBuffers(1, &vboId);
		glBindBuffer(GL_ARRAY_BUFFER, vboId);
		glBufferData(GL_ARRAY_BUFFER, 3 * n * sizeof(GLfloat), 0, GL_STATIC_DRAW);

		glGenBuffers(1, &cboId);
		glBindBuffer(GL_ARRAY_BUFFER, cboId);
		glBufferData(GL_ARRAY_BUFFER, 3 * n * sizeof(GLfloat), 0, GL_STATIC_DRAW);

		glEnableClientState(GL_VERTEX_ARRAY);
		glEnableClientState(GL_COLOR_ARRAY);

		glBindBuffer(GL_ARRAY_BUFFER, vboId);
		glBufferData(GL_ARRAY_BUFFER, 3 * n * sizeof(GLfloat), vertices, GL_STATIC_DRAW);
		glVertexPointer(3, GL_FLOAT, 0, NULL);

		glBindBuffer(GL_ARRAY_BUFFER, cboId);
		glBufferData(GL_ARRAY_BUFFER, 3 * n * sizeof(GLfloat), colors, GL_STATIC_DRAW);
		glColorPointer(3, GL_BYTE, 0, NULL);

		glPointSize(1.f);
		glDrawArrays(GL_POINTS, 0, n);

		glDisableClientState(GL_VERTEX_ARRAY);
		glDisableClientState(GL_COLOR_ARRAY);

		glfwSwapBuffers(window);
		glfwPollEvents();
	}
}

int render()
{
	GLFWwindow* window = initWindow(1024, 620);
	if (NULL != window)
	{
		display(window);
	}
	glfwDestroyWindow(window);
	glfwTerminate();
	return 0;
}

int main(int argc, char ** argv)
{
	render();
	return 0;
}