/*___INFO__MARK_BEGIN__*/
/*****************************************************************************
 *
 *  This code is the Property, a Trade Secret and the Confidential Information
 *  of Univa Corporation.
 *
 *  Copyright Univa Corporation. All Rights Reserved. Access is Restricted.
 *
 *  It is provided to you under the terms of the
 *  Univa Term Software License Agreement.
 *
 *  If you have any questions, please contact our Support Department.
 *
 *  www.univa.com
 *
 ****************************************************************************/
/*___INFO__MARK_END__*/
/* cuda_load_sensor.c */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "nvml.h"

#define MAXSTRSIZ 256

static char localHostName[MAXSTRSIZ];

static void
_getDeviceFreeMemory(nvmlDevice_t device, unsigned int nDevice) {
    nvmlReturn_t retval;
    nvmlMemory_t memory;

    if ((retval = nvmlDeviceGetMemoryInfo(device, &memory)) == NVML_SUCCESS) {
        printf("%s:cuda.%d.totalMem:%lld\n", localHostName, nDevice, memory.total);
        printf("%s:cuda.%d.freeMem:%lld\n", localHostName, nDevice, memory.free);
        printf("%s:cuda.%d.usedMem:%lld\n", localHostName, nDevice, memory.used);
    }
}

static void
_getDeviceECCErrorCounts(nvmlDevice_t device, unsigned int nDevice) {
    nvmlReturn_t retval;
    nvmlEnableState_t currentEccMode, pendingEccMode;

    if ((retval = nvmlDeviceGetEccMode(device, &currentEccMode, &pendingEccMode)) != NVML_SUCCESS) {
        currentEccMode = NVML_FEATURE_DISABLED;
    }

    /* Report this value regardless */
    printf("%s:cuda.%d.eccEnabled:%d\n", localHostName, nDevice, currentEccMode);

    if (currentEccMode == NVML_FEATURE_ENABLED) {
        unsigned long long eccCounts;

        retval = nvmlDeviceGetTotalEccErrors(device, NVML_SINGLE_BIT_ECC, NVML_VOLATILE_ECC, &eccCounts);

        if (retval == NVML_SUCCESS) {
            printf("%s:cuda.%d.volatileEccCount:%lld\n", localHostName, nDevice, eccCounts);
        }
    }
}

/**
 * Return metrics for device specified by 'device'
 */
static void
getDeviceMetrics(nvmlDevice_t device, unsigned int nDevice) {
    nvmlReturn_t retval;
    static char tmpStr[MAXSTRSIZ];
    unsigned int tmpUInt;

    /* Device name */
    retval = nvmlDeviceGetName(device, tmpStr, MAXSTRSIZ);
    if (retval == NVML_SUCCESS) {
        printf("%s:cuda.%d.name:%s\n", localHostName,
            nDevice, tmpStr);
    }

    /* Memory usage information */
    _getDeviceFreeMemory(device, nDevice);

    /* ECC error counts */
    _getDeviceECCErrorCounts(device, nDevice);

    /* Temperature */
    retval = nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &tmpUInt);
    if (retval == NVML_SUCCESS) {
        printf("%s:cuda.%d.temperature:%u\n", localHostName, nDevice, tmpUInt);
    }
}

static void
_getLoadSensorMetrics() {
    nvmlReturn_t retval;
    unsigned int deviceCount;
    unsigned int nDevice;
    static char tmpStr[MAXSTRSIZ];

    /* Get version string for NVIDIA driver currently installed */
    retval = nvmlSystemGetDriverVersion(tmpStr, MAXSTRSIZ);
    if (retval == NVML_SUCCESS) {
        printf("%s:cuda.verstr:%s\n", localHostName, tmpStr);
    }

    /* Return total number of GPU devices installed */
    retval = nvmlDeviceGetCount(&deviceCount);
    if (retval == NVML_SUCCESS) {
        printf("%s:cuda.devices:%u\n", localHostName, deviceCount);
    }

    /* Iterate over all devices */
    for (nDevice = 0; nDevice < deviceCount; nDevice++) {
        nvmlDevice_t device;

        retval = nvmlDeviceGetHandleByIndex(nDevice, &device);
        if (retval != NVML_SUCCESS) {
            /* TODO: how to properly handle this? */
            continue;
        }

        getDeviceMetrics(device, nDevice);
    }
}

int
main(int argc, char *argv[]) {
    nvmlReturn_t retval;

    gethostname(localHostName, MAXSTRSIZ);

    if ((retval = nvmlInit()) != NVML_SUCCESS) {
        fprintf(stderr, "Error: nvmlInit() failed (%d)\n", retval);
        exit(1);
    }

    while (1) {
        char inbuf[MAXSTRSIZ];
        size_t inlen;

        if (fgets(inbuf, MAXSTRSIZ, stdin) == NULL) {
            break;
        }

        /* Force a NULL terminator to prevent any chance of buffer overflow */
        inbuf[MAXSTRSIZ - 1] = '\0';

        inlen = strlen(inbuf);

        if ((inlen == 5) && strncasecmp(inbuf, "quit", inlen - 1) == 0) {
            break;
        }

        printf("begin\n");

        _getLoadSensorMetrics();

        printf("end\n");
        fflush(stdout);
    }

    nvmlShutdown();

    return EXIT_SUCCESS;
}
