###############################################################################
# Variable definitions for targets to build
###############################################################################
#___INFO__MARK_BEGIN__
#############################################################################
#
#  This code is the Property, a Trade Secret and the Confidential Information
#  of Univa Corporation.
#
#  Copyright Univa Corporation. All Rights Reserved. Access is Restricted.
#
#  It is provided to you under the terms of the
#  Univa Term Software License Agreement.
#
#  If you have any questions, please contact our Support Department.
#
#  www.univa.com
#
###########################################################################
#___INFO__MARK_END__
CUDA_TOOLKIT_HOME=/tools/PKG/cudatoolkit_4.0.17
CUDA_TOOLS_HOME=/tools/PKG/cudatools_4.0.17
NVIDIA_DRIVER_HOME=/tools/PKG/NVIDIA-driver-270.41.19

CC=gcc
CUDA_CFLAGS=-Wall -g -Wc++-compat -Werror
CUDA_INCLUDE=-I$(CUDA_TOOLKIT_HOME)/include -I$(CUDA_TOOLS_HOME)/NVML
CUDA_LDFLAGS=-L$(CUDA_TOOLKIT_HOME)/lib64 -L$(NVIDIA_DRIVER_HOME)
CUDA_LIBS=-lnvidia-ml

CUDA_SRC=cuda_load_sensor.c
CUDA_OBJS=$(CUDA_SRC:.c=.o)

# global rules: all, clean, depend
all: cuda_load_sensor

clean:
	$(RM) $(CUDA_OBJS) cuda_load_sensor

# rules to build the CUDA load sensor
cuda_load_sensor: $(CUDA_OBJS)
	$(CC) -o cuda_load_sensor $(CUDA_OBJS) $(CUDA_LDFLAGS) $(CUDA_LIBS)

# rules to build object codes
cuda_load_sensor.o: cuda_load_sensor.c
	$(CC) $(CUDA_CFLAGS) $(CUDA_INCLUDE) -c cuda_load_sensor.c

