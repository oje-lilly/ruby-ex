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
############################################################################
#___INFO__MARK_END_

# IMPORTANT: - Before compiling please check if LIBPATH and INCDIR are
#            set correctly.
#            - Test load sensor by calling on command line and then pressing
#            <enter> for sending a new line to load sensor. This triggers a
#            new measurement.

# DEFINES += -D MICACCESSAPI -D LINUX
CFLAGS += -m64 -g -O0 $(DEFINES)

LIBPATH = -L/usr/lib64/
LDFLAGS = $(LIBPATH) $(SCIF_LIBPATH) -lmicmgmt -lscif -lpthread
INCDIR = -I/usr/include

SOURCES=mic_help.c
APPS=load_sensor.c mic_load_check.c

OBJS = $(SOURCES:.c=.o)
BIN_OBJS = $(APPS:.c=.o)
BINARIES = $(APPS:.c=)

all: $(SOURCES) $(BINARIES)

load_sensor: $(OBJS) load_sensor.o
	$(CC) $(OBJS) load_sensor.o -o $@ $(LDFLAGS)

mic_load_check: $(OBJS) mic_load_check.o
	$(CC) $(OBJS) mic_load_check.o -o $@ $(LDFLAGS)

mic_help.o: mic_help.c
	$(CC) $(CFLAGS) $(INCDIR) -c mic_help.c -o mic_help.o

load_sensor.o: load_sensor.c
	$(CC) $(CFLAGS) $(INCDIR) -c load_sensor.c -o load_sensor.o

mic_load_check.o: mic_load_check.c
	$(CC) $(CFLAGS) $(INCDIR) -c mic_load_check.c -o mic_load_check.o

clean:
	$(RM) $(OBJS) $(BIN_OBJS) $(BINARIES)
