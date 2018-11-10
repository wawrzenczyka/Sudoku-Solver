
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <stdio.h>
#include <string>
#include <iostream>
#include <fstream>
#include <thrust/device_vector.h>
#include <thrust/extrema.h>
#include <set>


#define SIZE 9

typedef uint8_t byte;

struct Sudoku
{
	byte board[SIZE][SIZE];
	uint16_t rowNumbers[SIZE];
	uint16_t colNumbers[SIZE];
	uint16_t cellNumbers[SIZE];
	byte rowCounts[SIZE];
	byte colCounts[SIZE];
	byte cellCounts[SIZE];

	//bool active;

	__host__ __device__ Sudoku() { }

	__host__ __device__ Sudoku(byte board[SIZE][SIZE], uint16_t rowNumbers[SIZE], uint16_t colNumbers[SIZE],
		uint16_t cellNumbers[SIZE], byte rowCounts[SIZE], byte colCounts[SIZE], byte cellCounts[SIZE])
	{
		for (int i = 0; i < SIZE; i++)
		{
			this->rowNumbers[i] = rowNumbers[i];
			this->colNumbers[i] = colNumbers[i];
			this->cellNumbers[i] = cellNumbers[i];
			this->rowCounts[i] = rowCounts[i];
			this->colCounts[i] = colCounts[i];
			this->cellCounts[i] = cellCounts[i];
			for (int j = 0; j < SIZE; j++)
				this->board[i][j] = board[i][j];
		}
	}

	__host__ __device__ Sudoku& operator=(const Sudoku& old)
	{
		if (this != &old)
		{
			for (int i = 0; i < SIZE; i++)
			{
				this->rowNumbers[i] = old.rowNumbers[i];
				this->colNumbers[i] = old.colNumbers[i];
				this->cellNumbers[i] = old.cellNumbers[i];
				this->rowCounts[i] = old.rowCounts[i];
				this->colCounts[i] = old.colCounts[i];
				this->cellCounts[i] = old.cellCounts[i];
				for (int j = 0; j < SIZE; j++)
					this->board[i][j] = old.board[i][j];
			}
		}
		return *this;
	}
};

__host__ __device__ void PrintSudoku(byte arr[SIZE][SIZE])
{
	char s[200];
	int k = 0;
	for (int i = 0; i < SIZE; i++)
	{
		for (int j = 0; j < SIZE; j++)
		{
			s[k] = arr[i][j] + '0';
			s[k + 1] = j == SIZE - 1 ? '\n' : ' ';
			k += 2;
		}
	}
	s[k] = '\n';
	s[k + 1] = '\0';
	printf("%s", s);
}

__host__ __device__ void BoardToString(byte arr[SIZE][SIZE], char* s)
{
	int k = 0;
	for (int i = 0; i < SIZE; i++)
	{
		for (int j = 0; j < SIZE; j++)
		{
			s[k] = arr[i][j] + '0';
			s[k + 1] = j == SIZE - 1 ? '\n' : ' ';
			k += 2;
		}
	}
	s[k] = '\n';
	s[k + 1] = '\0';
}

__host__ __device__ byte GetBestCount(byte structure[])
{
	char max = -1;
	char index = -1;

	for (byte i = 0; i < SIZE; i++)
	{
		if (structure[i] > max && structure[i] < 9) 
		{
			max = structure[i];
			index = i;
		}
	}

	return (byte)index;
}

__host__ __device__ byte GetBestCountInRow(byte board[SIZE][SIZE], byte columnCounts[], byte row)
{
	char max = -1;
	char index = -1;

	for (byte j = 0; j < SIZE; j++)
	{
		if (board[row][j] == 0 && columnCounts[j] > max)
		{
			max = (char)columnCounts[j];
			index = j;
		}
	}

	return (byte)index;
}

__host__ __device__ bool IsNumberInRowOrColumn(uint16_t structure, byte number)
{
	return structure & (1U << number);
}

__host__ __device__ void AddNumberToRowOrColumn(uint16_t& structure, byte number)
{
	if (number != 0)
	{
		structure |= (1U << number);
	}
}

__host__ __device__ void RemoveNumberFromRowOrColumn(uint16_t& structure, byte number)
{
	if (number != 0)
	{
		structure &= ~(1U << number);
	}
}

__host__ __device__ void PrintRowsOrColumns(uint16_t structure[])
{
	for (byte i = 0; i < SIZE; i++)
	{
		for (byte number = 1; number <= SIZE; number++)
		{
			printf("%d ", (int)IsNumberInRowOrColumn(structure[i], number));
			if (number % (SIZE + 1) == SIZE)
				printf("\n");
		}
	}
	printf("\n");
}

__host__ __device__ byte cell(byte i, byte j)
{
	return (i / 3) * 3 + j / 3;
}

__global__ void activeResetKernel(int* d_active, int n)
{
	int i = (blockIdx.x * blockDim.x) + threadIdx.x;
	if (i >= n)
		return;

	d_active[i] = false;
}

__global__ void copyKernel(Sudoku* d_sudokus, Sudoku* d_sudokus_target, int* d_active, int* d_active_scan, int* d_active_copy, int n, int newMax)
{
	int i = (blockIdx.x * blockDim.x) + threadIdx.x;

	if (i == 0)
		return;

	if (i < n && d_active_copy[i] == true)
	{
		memcpy(d_sudokus_target + d_active_scan[i], d_sudokus + i, sizeof(Sudoku));
		d_active[d_active_scan[i]] = true;
	}
}

__global__ void copyActiveKernel(int* d_active, int* d_active_copy, int n)
{
	int i = (blockIdx.x * blockDim.x) + threadIdx.x;

	if (i < n)
	{
		d_active_copy[i] = d_active[i];
	}
}

__global__ void sudokuKernel(Sudoku* d_sudokus, int* d_active, int n)
{
	int i = (blockIdx.x * blockDim.x) +  threadIdx.x;

	if (i > n)
		return;

	if (d_active[0] == true)
	{
		return;
	}

	Sudoku mySudoku;
	memcpy(&mySudoku, d_sudokus + i, sizeof(Sudoku));

	if (d_active[i] == false)
	{
		return;
	}

	byte row = GetBestCount(mySudoku.rowCounts);
	if (row == (byte)-1) 
	{
		memcpy(d_sudokus, &mySudoku, sizeof(Sudoku));
		d_active[0] = true;
		return;
	}
	byte col = GetBestCountInRow(mySudoku.board, mySudoku.colCounts, row);
	byte cellnr = cell(row, col);

	for (byte number = 1; number <= SIZE; number++)
	{
		if (!IsNumberInRowOrColumn(mySudoku.rowNumbers[row], number) &&
			!IsNumberInRowOrColumn(mySudoku.colNumbers[col], number) &&
			!IsNumberInRowOrColumn(mySudoku.cellNumbers[cellnr], number))
		{
			mySudoku.board[row][col] = number;

			AddNumberToRowOrColumn(mySudoku.rowNumbers[row], number);
			AddNumberToRowOrColumn(mySudoku.colNumbers[col], number);
			AddNumberToRowOrColumn(mySudoku.cellNumbers[cellnr], number);
			mySudoku.rowCounts[row]++;
			mySudoku.colCounts[col]++;
			mySudoku.cellCounts[cellnr]++;

			int index = n + 1 + (i - 1) * SIZE + (number - 1);
			memcpy(d_sudokus + index, &mySudoku, sizeof(Sudoku));
			d_active[index] = true;

			RemoveNumberFromRowOrColumn(mySudoku.rowNumbers[row], number);
			RemoveNumberFromRowOrColumn(mySudoku.colNumbers[col], number);
			RemoveNumberFromRowOrColumn(mySudoku.cellNumbers[cellnr], number);
			mySudoku.rowCounts[row]--;
			mySudoku.colCounts[col]--;
			mySudoku.cellCounts[cellnr]--;
			mySudoku.board[row][col] = 0;
		}
	}
	d_active[i] = false;
}

void ReadSudoku(byte arr[SIZE][SIZE], std::string filename)
{
	std::ifstream stream;
	stream.open(filename.c_str());

	char c = stream.get();
	byte i = 0, j = 0;

	while (stream.good() && c != '\n') 
	{
		if (c != 'x' && c != '0')
		{
			int n = atoi(&c);
			arr[i][j] = n;
		}
		else
			arr[i][j] = 0;

		c = stream.get();
		j++;
		if (j == SIZE)
		{
			j = 0;
			i++;
		}
	}
	stream.close();
}

void GetRowColNumbers(byte sudoku[SIZE][SIZE], uint16_t rows[], uint16_t columns[], uint16_t areas[])
{
	for (byte i = 0; i < SIZE; i++)
	{
		rows[i] = 0;
		columns[i] = 0;
		areas[i] = 0;
	}

	for (byte i = 0; i < SIZE; i++)
	{
		for (byte j = 0; j < SIZE; j++)
		{
			if (sudoku[i][j] != 0)
			{
				AddNumberToRowOrColumn(rows[i], sudoku[i][j]);
				AddNumberToRowOrColumn(columns[j], sudoku[i][j]);
				AddNumberToRowOrColumn(areas[cell(i, j)], sudoku[i][j]);
			}
		}
	}
}

void GetRowColCounts(uint16_t rows[], uint16_t columns[], uint16_t cells[], byte rowCounts[], byte columnCounts[], byte cellCounts[])
{
	for (byte i = 0; i < SIZE; i++)
	{
		rowCounts[i] = 0;
		columnCounts[i] = 0;
		cellCounts[i] = 0;
	}

	for (byte i = 0; i < SIZE; i++)
	{
		for (byte number = 1; number <= SIZE; number++)
		{
			if (IsNumberInRowOrColumn(rows[i], number))
				rowCounts[i]++;
			if (IsNumberInRowOrColumn(columns[i], number))
				columnCounts[i]++;
			if (IsNumberInRowOrColumn(cells[i], number))
				cellCounts[i]++;
		}
	}
}

cudaError_t PrepareSudoku(byte sudokuArray[SIZE][SIZE])
{
	uint16_t rowNumbers[SIZE];
	uint16_t colNumbers[SIZE];
	uint16_t cellNumbers[SIZE];	
	byte rowCounts[SIZE];
	byte colCounts[SIZE];
	byte cellCounts[SIZE];

	GetRowColNumbers(sudokuArray, rowNumbers, colNumbers, cellNumbers);
	GetRowColCounts(rowNumbers, colNumbers, cellNumbers, rowCounts, colCounts, cellCounts);

	cudaError_t cudaStatus;

	Sudoku activeSudoku(sudokuArray, rowNumbers, colNumbers, cellNumbers, rowCounts, colCounts, cellCounts);

	cudaEvent_t start, stop;
	float time;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	cudaEventRecord(start, 0);

	int activeBlocks = 1;
	Sudoku *d_sudokus;
	Sudoku *d_sudokus_target;

	Sudoku *h_sudokus = (Sudoku*)malloc((activeBlocks + 1) * sizeof(Sudoku));
	if (h_sudokus == NULL) {
		fprintf(stderr, "malloc failed!");
		return cudaStatus;
	}
	int *d_active;
	int *d_active_copy;
	int *d_active_scan;

	int *h_active = (int*)malloc((activeBlocks + 9 * activeBlocks + 1) * sizeof(int));
	if (h_active == NULL) {
		fprintf(stderr, "malloc failed!");
		return cudaStatus;
	}

	for (int i = 0; i < (activeBlocks + 1); i++) {
		if (i == 1)
		{
			memcpy(h_sudokus + i, &activeSudoku, sizeof(Sudoku));
		}
	}

	for (int i = 0; i < (activeBlocks + 9 * activeBlocks + 1); i++) {
		if (i == 1)
		{
			h_active[i] = true;
		}
		else
		{
			h_active[i] = false;
		}
	}

	cudaStatus = cudaMalloc((void**)&d_sudokus, (activeBlocks + 9 * activeBlocks + 1) * sizeof(Sudoku));
	if (cudaStatus != cudaSuccess) {
		cudaEventRecord(stop, 0);
		cudaEventSynchronize(stop);
		cudaEventElapsedTime(&time, start, stop);
		printf("Time for the kernel: %f ms\n", time);

		printf("Not enough memory to solve this sudoku!\n");
		//fprintf(stderr, "cudaMalloc failed!");
		free(h_active);
		free(h_sudokus);
		cudaFree(d_sudokus);
		return cudaStatus;
	}

	cudaStatus = cudaMemcpy(d_sudokus, h_sudokus, (activeBlocks + 1) * sizeof(Sudoku), cudaMemcpyHostToDevice);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMemcpy failed!");
		free(h_active);
		free(h_sudokus);
		cudaFree(d_sudokus);
		return cudaStatus;
	}

	cudaStatus = cudaMalloc((void**)&d_active, (activeBlocks + 9 * activeBlocks + 1) * sizeof(int));
	if (cudaStatus != cudaSuccess) {
		cudaEventRecord(stop, 0);
		cudaEventSynchronize(stop);
		cudaEventElapsedTime(&time, start, stop);
		printf("Time for the kernel: %f ms\n", time);
		printf("Not enough memory to solve this sudoku!\n");
		//fprintf(stderr, "cudaMalloc failed!");
		free(h_active);
		free(h_sudokus);
		cudaFree(d_sudokus);
		cudaFree(d_active);
		return cudaStatus;
	}

	cudaStatus = cudaMalloc((void**)&d_active_scan, (activeBlocks + 9 * activeBlocks + 1) * sizeof(int));
	if (cudaStatus != cudaSuccess) {
		cudaEventRecord(stop, 0);
		cudaEventSynchronize(stop);
		cudaEventElapsedTime(&time, start, stop);
		printf("Time for the kernel: %f ms\n", time);
		printf("Not enough memory to solve this sudoku!\n");
		//fprintf(stderr, "cudaMalloc failed!");
		free(h_active);
		free(h_sudokus);
		cudaFree(d_sudokus);
		cudaFree(d_active);
		cudaFree(d_active_scan);
		return cudaStatus;
	}

	cudaStatus = cudaMemcpy(d_active, h_active, (activeBlocks + 9 * activeBlocks + 1) * sizeof(int), cudaMemcpyHostToDevice);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMemcpy failed!");
		free(h_active);
		free(h_sudokus);
		cudaFree(d_sudokus);
		cudaFree(d_active);
		cudaFree(d_active_scan);
		return cudaStatus;
	}

	thrust::device_ptr<int> dev_active_ptr(d_active);
	thrust::device_ptr<int> dev_active_scan_ptr(d_active_scan);

	int i = 0;
	bool lastActive;
	while (1)
	{
		if (activeBlocks <= 0)
		{
			cudaEventRecord(stop, 0);
			cudaEventSynchronize(stop);
			cudaEventElapsedTime(&time, start, stop);
			printf("Time for the kernel: %f ms\n", time);

			printf("Sudoku:\n");
			PrintSudoku(sudokuArray);
			printf("This sudoku doesn't have a solution!\n");
			return cudaStatus;
		}

		i++;
		printf("Iteration: %d, active blocks - %d\n", i, activeBlocks);

		sudokuKernel <<<(activeBlocks + 1)/1024 + 1, 1024>>>(d_sudokus, d_active, activeBlocks);
			cudaStatus = cudaGetLastError();
			if (cudaStatus != cudaSuccess) {
				fprintf(stderr, "sudokuKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
				free(h_active);
				free(h_sudokus);
				cudaFree(d_sudokus);
				cudaFree(d_active);
				cudaFree(d_active_scan);
				return cudaStatus;
			}

			cudaStatus = cudaDeviceSynchronize();
			if (cudaStatus != cudaSuccess) {
				fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching sudokuKernel!\n", cudaStatus);
				free(h_active);
				free(h_sudokus);
				cudaFree(d_sudokus);
				cudaFree(d_active);
				cudaFree(d_active_scan);
				return cudaStatus;
			}

		if (dev_active_ptr[0] == true)
		{
			printf("Solution found!\n");
			break;
		}

		activeBlocks = activeBlocks + activeBlocks * 9;

		dev_active_ptr[0] = true;
		thrust::exclusive_scan(dev_active_ptr, dev_active_ptr + activeBlocks + 1, dev_active_scan_ptr);
		dev_active_ptr[0] = false;
		int newActive = thrust::max_element(dev_active_scan_ptr, dev_active_scan_ptr + activeBlocks + 1)[0];

		lastActive = dev_active_ptr[activeBlocks];
		if (lastActive)
			newActive++;

		cudaStatus = cudaMalloc((void**)&d_sudokus_target, (activeBlocks + 9 * activeBlocks + 1) * sizeof(Sudoku));
		if (cudaStatus != cudaSuccess) {
			cudaEventRecord(stop, 0);
			cudaEventSynchronize(stop);
			cudaEventElapsedTime(&time, start, stop);
			printf("Time for the kernel: %f ms\n", time);
			printf("Not enough memory to solve this sudoku!\n");
			//fprintf(stderr, "cudaMalloc failed!");
			free(h_active);
			free(h_sudokus);
			cudaFree(d_sudokus);
			cudaFree(d_sudokus_target);
			cudaFree(d_active);
			cudaFree(d_active_scan);
			return cudaStatus;
		}

		cudaStatus = cudaMalloc((void**)&d_active_copy, (activeBlocks + 1) * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			cudaEventRecord(stop, 0);
			cudaEventSynchronize(stop);
			cudaEventElapsedTime(&time, start, stop);
			printf("Time for the kernel: %f ms\n", time);
			printf("Not enough memory to solve this sudoku!\n");
			//fprintf(stderr, "cudaMalloc failed!");
			free(h_active);
			free(h_sudokus);
			cudaFree(d_sudokus);
			cudaFree(d_sudokus_target);
			cudaFree(d_active);
			cudaFree(d_active_scan);
			cudaFree(d_active_copy);
			return cudaStatus;
		}
		
		copyActiveKernel << <(activeBlocks + 1) / 1024 + 1, 1024 >> >(d_active, d_active_copy, (activeBlocks + 1));
			cudaStatus = cudaGetLastError();
			if (cudaStatus != cudaSuccess) {
				fprintf(stderr, "copyActiveKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
				free(h_active);
				free(h_sudokus);
				cudaFree(d_sudokus);
				cudaFree(d_sudokus_target);
				cudaFree(d_active);
				cudaFree(d_active_scan);
				cudaFree(d_active_copy);
				return cudaStatus;
			}

			cudaStatus = cudaDeviceSynchronize();
			if (cudaStatus != cudaSuccess) {
				fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching copyActiveKernel!\n", cudaStatus);
				free(h_active);
				free(h_sudokus);
				cudaFree(d_sudokus);
				cudaFree(d_sudokus_target);
				cudaFree(d_active);
				cudaFree(d_active_scan);
				cudaFree(d_active_copy);
				return cudaStatus;
			}


		cudaFree(d_active);
		cudaStatus = cudaMalloc((void**)&d_active, (activeBlocks + 9 * activeBlocks + 1) * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			cudaEventRecord(stop, 0);
			cudaEventSynchronize(stop);
			cudaEventElapsedTime(&time, start, stop);
			printf("Time for the kernel: %f ms\n", time);
			printf("Not enough memory to solve this sudoku!\n");
			//fprintf(stderr, "cudaMalloc failed!");
			free(h_active);
			free(h_sudokus);
			cudaFree(d_sudokus);
			cudaFree(d_sudokus_target);
			cudaFree(d_active);
			cudaFree(d_active_scan);
			cudaFree(d_active_copy);
			return cudaStatus;
		}
		
		dev_active_ptr = thrust::device_ptr<int>(d_active);

		activeResetKernel <<<(activeBlocks + 9 * activeBlocks + 1) / 1024 + 1, 1024 >>>(d_active, (activeBlocks + 9 * activeBlocks + 1));
			cudaStatus = cudaGetLastError();
			if (cudaStatus != cudaSuccess) {
				fprintf(stderr, "activeResetKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
				free(h_active);
				free(h_sudokus);
				cudaFree(d_sudokus);
				cudaFree(d_sudokus_target);
				cudaFree(d_active);
				cudaFree(d_active_scan);
				cudaFree(d_active_copy);
				return cudaStatus;
			}

			cudaStatus = cudaDeviceSynchronize();
			if (cudaStatus != cudaSuccess) {
				fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching activeResetKernel!\n", cudaStatus);
				free(h_active);
				free(h_sudokus);
				cudaFree(d_sudokus);
				cudaFree(d_sudokus_target);
				cudaFree(d_active);
				cudaFree(d_active_scan);
				cudaFree(d_active_copy);
				return cudaStatus;
			}


		copyKernel << <(activeBlocks + 1) / 1024 + 1, 1024 >> >(d_sudokus, d_sudokus_target, d_active, d_active_scan, d_active_copy, (activeBlocks + 1), newActive);
			cudaStatus = cudaGetLastError();
			if (cudaStatus != cudaSuccess) {
				fprintf(stderr, "copyKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
				free(h_active);
				free(h_sudokus);
				cudaFree(d_sudokus);
				cudaFree(d_sudokus_target);
				cudaFree(d_active);
				cudaFree(d_active_scan);
				cudaFree(d_active_copy);
				return cudaStatus;
			}

			cudaStatus = cudaDeviceSynchronize();
			if (cudaStatus != cudaSuccess) {
				fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching copyKernel!\n", cudaStatus);
				free(h_active);
				free(h_sudokus);
				cudaFree(d_sudokus);
				cudaFree(d_sudokus_target);
				cudaFree(d_active);
				cudaFree(d_active_scan);
				cudaFree(d_active_copy);
				return cudaStatus;
			}

		cudaFree(d_active_scan);
		cudaStatus = cudaMalloc((void**)&d_active_scan, (activeBlocks + 9 * activeBlocks + 1) * sizeof(int));
		if (cudaStatus != cudaSuccess) {
			cudaEventRecord(stop, 0);
			cudaEventSynchronize(stop);
			cudaEventElapsedTime(&time, start, stop);
			printf("Time for the kernel: %f ms\n", time);
			printf("Not enough memory to solve this sudoku!\n");
			//fprintf(stderr, "cudaMalloc failed!");
			free(h_active);
			free(h_sudokus);
			cudaFree(d_sudokus);
			cudaFree(d_sudokus_target);
			cudaFree(d_active);
			cudaFree(d_active_scan);
			cudaFree(d_active_copy);
			return cudaStatus;
		}
		
		dev_active_scan_ptr = thrust::device_ptr<int>(d_active_scan);

		cudaFree(d_sudokus);
		cudaFree(d_active_copy);
		d_sudokus = d_sudokus_target;

		activeBlocks = newActive - 1;
	}

	cudaStatus = cudaMemcpy(h_sudokus, d_sudokus, 1 * sizeof(Sudoku), cudaMemcpyDeviceToHost);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMemcpy failed!");
		free(h_active);
		free(h_sudokus);
		cudaFree(d_sudokus);
		cudaFree(d_active);
		cudaFree(d_active_scan);
		return cudaStatus;
	}

	cudaEventRecord(stop, 0);
	cudaEventSynchronize(stop);
	cudaEventElapsedTime(&time, start, stop);
	printf("Time for the kernel: %f ms\n", time);

	printf("Original:\n");
	PrintSudoku(sudokuArray);
	printf("Solved:\n");
	PrintSudoku(h_sudokus[0].board);

	free(h_active);
	free(h_sudokus);
	cudaFree(d_sudokus);
	cudaFree(d_active);
	cudaFree(d_active_scan);

	return cudaStatus;
}

int main()
{
	byte sudoku[SIZE][SIZE];
	cudaError_t cudaStatus;

	printf("Entry:\n");
	ReadSudoku(sudoku, "Entry.txt");
	cudaStatus = PrepareSudoku(sudoku);
	if (cudaStatus != cudaSuccess) {
		printf("Solution not found!\n");
		//fprintf(stderr, "PrepareSudoku failed!");
		return 1;
	}
	getchar();
	printf("------------------------------------------------------------\n");

	printf("Easy:\n");
	ReadSudoku(sudoku, "Easy.txt");
	cudaStatus = PrepareSudoku(sudoku);
	if (cudaStatus != cudaSuccess) {
		printf("Solution not found!\n");
		//fprintf(stderr, "PrepareSudoku failed!");
		return 1;
	}
	getchar();
	printf("------------------------------------------------------------\n");

	printf("Medium:\n");
	ReadSudoku(sudoku, "Medium.txt");
	cudaStatus = PrepareSudoku(sudoku);
	if (cudaStatus != cudaSuccess) {
		printf("Solution not found!\n");
		//fprintf(stderr, "PrepareSudoku failed!");
		return 1;
	}
	getchar();
	printf("------------------------------------------------------------\n");

	printf("Hard:\n");
	ReadSudoku(sudoku, "Hard.txt");
	cudaStatus = PrepareSudoku(sudoku);
	if (cudaStatus != cudaSuccess) {
		printf("Solution not found!\n");
		//fprintf(stderr, "PrepareSudoku failed!");
		return 1;
	}
	getchar();
	printf("------------------------------------------------------------\n");

	printf("Evil:\n");
	ReadSudoku(sudoku, "Evil.txt");
	cudaStatus = PrepareSudoku(sudoku);
	if (cudaStatus != cudaSuccess) {
		printf("Solution not found!\n");
		//fprintf(stderr, "PrepareSudoku failed!");
		return 1;
	}
	getchar();
    return 0;
}