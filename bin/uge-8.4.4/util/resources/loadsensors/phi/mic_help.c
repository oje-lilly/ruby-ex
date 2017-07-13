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
/**
 * THIS IS AN EXAMPLE HOW TO ACCESS LOAD METRICS FOR
 * INTEL XEON PHI CARDS PROGRAMATICALLY. THE CODE IS
 * ONLY FOR DEMONSTRATION PURPOSES.
 *
 * Note: - MicAccessSDK was deprecated with MPSS 3.2. The version below
 *         is working on the MicManagementAPI (see man libmicmgmt) and
 *         tested with MPSS 3.4.1.
 *       - flash version is not available
 *       - board temperature is not available
 **/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <stdbool.h>

#include "mic_help.h"
#include <miclib.h>

#define MAX_STRING 1024

#define true  1
#define false 0

/* the default values should be alligned with uge_phi_load_sensor_install.sh */

bool show_memory_utilization = true;
bool show_die_temperature    = true;
bool show_board_temperature  = false;
bool show_mem_temperature    = false;
bool show_inlet_temperature  = true;
bool show_outlet_temperature = true;
bool show_fanstatus          = false;
bool show_powerusage         = true;
bool show_powerlimit_physical = false;
bool show_powerlimit_upper_threshold = false;
bool show_powerlimit_lower_threshold = false;
bool show_flash_version      = false;
bool show_driver_version     = true;
bool show_uos_version        = true;
bool show_ecc_state          = true;
bool show_active_cores       = true;

/* API Helpers */

void initAdapter(struct mic_device ** accessHandle, int adapter)
{
   int error = 0;
   if ((error = mic_open_device(accessHandle, (uint32_t)adapter)) != 0) {
      printf ("Error %d during opening device %d.\n", error, adapter);
      exit(1);
   }
}

void closeAdapter(struct mic_device * accessHandle) {
   int error = 0;
   if ((error = mic_close_device(accessHandle)) != 0) {
      printf ("Error %d during closing device.\n", error);
      exit(1);
    }
}

/* Device metrics reporting functions */
static void report_memory(struct mic_device * accessHandle, const int devId,
                             const char* hostname, uint32_t *total_max, 
                             uint32_t *free_max, uint32_t *used_min) {
   if (show_memory_utilization) {
      uint32_t total = 0;
      uint32_t free  = 0;
      uint32_t buff  = 0;
      int error = 0;
      struct mic_memory_util_info * memory = NULL;

      if ((error = mic_get_memory_utilization_info(accessHandle, &memory)) != 0) {
         return;
      }
 
      if (mic_get_total_memory_size(memory, &total) != 0) {
         // reset it to 0 in case of an error
         total = 0;
      }

      if (mic_get_available_memory_size(memory, &free) != 0) {
         // reset it to 0 in case of an error
         free = 0;
      }

      if (mic_get_memory_buffers_size(memory, &buff) != 0) {
         // reset it to 0 in case of an error
         total = 0;
      }

      printf("%smic.%d.mem_total:%uK\n", hostname, devId, total);
      printf("%smic.%d.mem_free:%uK\n", hostname, devId, free);
      printf("%smic.%d.mem_used:%uK\n", hostname, devId, (total - free));
      printf("%smic.%d.mem_bufs:%uK\n", hostname, devId, buff);

      if (*total_max < total) {
         *total_max = total;
      }

      if (*free_max < free) {
         *free_max = free;
      }

      if (*used_min > (total - free)) {
         *used_min = (total - free);
      }
      mic_free_memory_utilization_info(memory);
   }
}

/* Report host global memory related values */
static void report_global_memory(const char* hostname, uint32_t total_max, uint32_t free_max, uint32_t used_min) {
   if (show_memory_utilization) {
      printf("%smic_mem_total_max:%uK\n", hostname, total_max);
      printf("%smic_mem_free_max:%uK\n", hostname, free_max);
      printf("%smic_mem_used_min:%uK\n", hostname, used_min);
   }
}

static void report_temperature(struct mic_device * accessHandle, const int devId, const char* hostname,
                               uint32_t* max_die, uint32_t* max_board, uint32_t* max_inlet, uint32_t* max_outlet,
                               uint32_t* max_mem) {
   int error = 0;
   int valid = 0;
   struct mic_thermal_info * thermal = NULL;

   if ((error = mic_get_thermal_info(accessHandle, &thermal)) != 0) {
      return;
   }

   if ((error = mic_is_die_temp_valid(thermal, &valid)) == 0 && valid != 0) {
      // die temperature is valid
      uint32_t temp = 0;
      if ((error = mic_get_die_temp(thermal, &temp)) == 0) {
         // degrees Celsius
         printf("%smic.%d.temp_die:%u\n",hostname, devId, temp);
         if (*max_die < temp) 
            *max_die = temp; 
      }
   }

   if ((error = mic_is_gddr_temp_valid(thermal, &valid)) == 0 && valid != 0) {
      // memory (ddr) temperature is valid
      uint16_t temp = 0;
      if ((error = mic_get_gddr_temp(thermal, &temp)) == 0) {
         // degrees Celsius
         printf("%smic.%d.temp_mem:%u\n",hostname, devId, temp);
         if (*max_inlet < temp) 
            *max_inlet = temp; 
      }
   }

   if ((error = mic_is_fanin_temp_valid(thermal, &valid)) == 0 && valid != 0) {
      // fanin temperature is valid
      uint16_t temp = 0;
      if ((error = mic_get_fanin_temp(thermal, &temp)) == 0) {
         // degrees Celsius
         printf("%smic.%d.temp_inlet:%u\n",hostname, devId, temp);
         if (*max_inlet < temp) 
            *max_inlet = temp; 
      }
   }

   if ((error = mic_is_fanout_temp_valid(thermal, &valid)) == 0 && valid != 0) {
      // fanout temperature is valid
      uint16_t temp = 0;
      if ((error = mic_get_fanout_temp(thermal, &temp)) == 0) {
         // degrees Celsius
         printf("%smic.%d.temp_outlet:%u\n",hostname, devId, temp);
         if (*max_outlet < temp) 
            *max_outlet = temp; 
      }
   }

   // TODO temp_board is missing?
   mic_free_thermal_info(thermal);
}

static void report_global_temperature(const char* hostname, uint32_t max_die, uint32_t max_board, uint32_t max_inlet,
                                      uint32_t max_outlet, uint32_t max_mem) {
   if (show_die_temperature) {
      printf("%smic_temp_die_max:%u\n", hostname, max_die);
   }
   if (show_board_temperature) {
      printf("%smic_temp_board_max:%u\n", hostname, max_board);
   }
   if (show_inlet_temperature) {
      printf("%smic_temp_inlet_max:%u\n", hostname, max_inlet);
   }
   if (show_outlet_temperature) {
      printf("%smic_temp_outlet_max:%u\n", hostname, max_outlet);
   }
   if (show_mem_temperature) {
      printf("%smic_temp_mem_max:%u\n", hostname, max_mem);
   }
}

static void report_fanstatus(struct mic_device * accessHandle, const int devId, const char* hostname) {
   int error = 0;
   uint32_t rpm = 0;
   struct mic_thermal_info * thermal = NULL;

   if (mic_get_thermal_info(accessHandle, &thermal) != 0) {
      return;
   }
   if (mic_get_fan_rpm(thermal, &rpm) == 0 && rpm > 0) {
      printf("%smic.%d.fan:%s\n",hostname, devId, "TRUE");
   } else {
      printf("%smic.%d.fan:%s\n",hostname, devId, "FALSE");
   }
   mic_free_thermal_info(thermal);
}

static void report_powerusage(struct mic_device * accessHandle, const int devId,
                                 const char* hostname, uint32_t *power_usage) {
   if (show_powerusage) {
      struct mic_power_util_info *power_info = NULL;
      uint32_t power = 0;
      uint32_t watt  = 0;

      if (mic_get_power_utilization_info(accessHandle, &power_info) != 0) {
         return;
      }
      // please consult the Intel documentation about the measurement
      // window 0 definition
      if (mic_get_total_power_readings_w0(power_info, &power) == 0) {
         watt = power / 1000000;
      }
      printf("%smic.%d.power:%u\n", hostname, devId, watt);
      *power_usage += watt;

      mic_free_power_utilization_info(power_info);
   }
}

static void report_global_powerusage(const char* hostname, uint32_t combined_power) {
   if (show_powerusage) {
      printf("%smic_power_combined:%u\n", hostname, combined_power);
   }
}

static void report_powerlimit(struct mic_device * accessHandle, const int devId,
                                 const char* hostname) {
   struct mic_power_limit *limit = NULL;
   uint32_t physLimit = 0;
   uint32_t powerHigh = 0;
   uint32_t powerLow  = 0; 
   
   if (show_powerlimit_physical == false && show_powerlimit_upper_threshold == false
          && show_powerlimit_lower_threshold == false) {
      return;
   }

   if (mic_get_power_limit(accessHandle, &limit) != 0) {
      return;
   }

   if (mic_get_power_phys_limit(limit, &physLimit) != 0) {
      physLimit = 0;
   }

   if (mic_get_power_hmrk(limit, &powerHigh) != 0) {
      powerHigh = 0;
   }

   if (mic_get_power_lmrk(limit, &powerLow) != 0) {
      powerLow = 0;
   }

   mic_free_power_limit(limit);

   if (show_powerlimit_physical) {
      printf("%smic.%d.power_physical_limit:%u\n", physLimit);
   }

   if (show_powerlimit_upper_threshold) {
      printf("%smic.%d.power_upper_threshold:%u\n", powerHigh);
   }

   if (show_powerlimit_lower_threshold) {
      printf("%smic.%d.power_lower_threshold:%u\n", powerLow);
   }
}

static void report_uosversion(struct mic_device * accessHandle, const int devId,
                                 const char* hostname) {
   if (show_uos_version) {
      struct mic_version_info *info = NULL;
      char version[MAX_STRING];
      size_t len = MAX_STRING;
    
      if (mic_get_version_info(accessHandle, &info) != 0) {
         return;
      }

      if (mic_get_uos_version(info, version, &len) == 0) {
         printf("%smic.%d.uos_version:%s\n", hostname, devId, version);
      }
      
      mic_free_version_info(info);
   }
}

static void report_ECCstate(struct mic_device * accessHandle, const int devId,
                             const char* hostname) {
   if (show_ecc_state) {
      uint16_t ecc = 0;
      struct mic_device_mem * info = NULL;
      if (mic_get_memory_info(accessHandle, &info) != 0) {
         return;
      }
      if (mic_get_ecc_mode(info, &ecc) != 0) {
         return;
      }
      printf("%smic.%d.ecc_on:%s\n", hostname, devId, (ecc != 0)?"TRUE":"FALSE");
      mic_free_memory_info(info);
   }
}

static void report_numcores(struct mic_device * accessHandle, const int devId,
                              const char* hostname, uint32_t* cores, uint32_t* max) {
   if (show_active_cores) {
      struct mic_cores_info *info = NULL;
      uint32_t count = 0;

      if (mic_get_cores_info(accessHandle, &info) != 0) {
         return;
      }
      if (mic_get_cores_count(info, &count) == 0) {
         printf("%smic.%d.cores:%u\n", hostname, devId, count);
         *cores += count;
         if (*max < count) {
            *max = count;
         }
      }
      // core frequencies are handle best here...
      mic_free_cores_info(info);
   }
}

static void report_global_numcores(const char* hostname, uint32_t combined_cores,
                                      uint32_t cores_max) {
   if (show_active_cores) {
      printf("%smic_cores_combined:%u\n", hostname, combined_cores);
      printf("%smic_cores_max:%u\n", hostname, cores_max);
   }
}

/**
 * @brief Returns the amount of Intel Xeon Phi cards installed.
 *
 * MPSS system service must be running.
 *
 * @return Amount of cards.
 */
int get_amount_of_cards() {
   struct mic_devices_list * dl = NULL;
   int nAdapters = 0;
   if (mic_get_devices(&dl) == 0) {
      if (mic_get_ndevices(dl, &nAdapters) == 0) {
         mic_free_devices(dl);
         return nAdapters;
      }
      mic_free_devices(dl);
   }
   return (int) nAdapters;
}

/**
 * @brief Reports the load for one or all MIC cards.
 *
 * Prints out a number of load values for one or all MIC cards.
 * If the card_nr is -1 the metrics for all cards are reported.
 * This includes global minimum or maximum values (like
 * highest temperature for all cards). The load values must be
 * configured before this function is called. If no configuration
 * is the default values are set.
 *
 * MPSS system service must be running.
 *
 * @param hostName The hostname which is prefix in the output.
 * @param card_nr Either -1 if all cards are reported or the card number.
 */
void load_sensor(const char *hostName, const int card_nr) {
   struct mic_devices_list * dl = NULL;
   //mic_device adaptersList[256];
   struct mic_device * accessHandle = NULL;
   uint32_t nAdapters = 0;
   uint32_t adapterNum;
   /* host global min, max, and combined values */
   uint32_t total_max = 0;
   uint32_t free_max  = 0;
   uint32_t used_min  = INT32_MAX;
   /* temperature based */
   uint32_t max_die    = 0;
   uint32_t max_board  = 0;
   uint32_t max_inlet  = 0;
   uint32_t max_outlet = 0;
   uint32_t max_mem    = 0;
   /* sum of power usage from all cards */
   uint32_t combined_power = 0;
   /* sum of all active cores */
   uint32_t num_cores   = 0;
   uint32_t max_cores   = 0;
   int start_at_adapter = 0;
   const char* localHostName = NULL;

   if (strcmp(hostName, "") != 0) {
      /* append a ":" at the end of the hostname as a delimiter */
      char* name = malloc(sizeof(char)*strlen(hostName) + 2);
      strncpy(name, hostName, strlen(hostName));
      name[strlen(hostName)] = ':'; /* append ':\0' */
      name[strlen(hostName)+1] = '\0';
      localHostName = name;

   } else {
      localHostName = hostName;
   }

   // initMicAPI(&accessHandle, adaptersList, &nAdapters);
   if (mic_get_devices(&dl) != 0) {
      printf("Error duing mic_get_devices() call. Abort.\n");
      exit(1);
   }
   // get amount of installed mics
   if (mic_get_ndevices(dl, &nAdapters) != 0) {
      printf("Error during mic_get_ndevices(). Abort.\n");
      exit(1);
   }

   /* only report values for a specific adapter */
   if (card_nr >= 0) {
      start_at_adapter = card_nr;
   }

   for (adapterNum = start_at_adapter; adapterNum < nAdapters; adapterNum++) {
      // open mic device
      initAdapter(&accessHandle, adapterNum);

      /* If temperature should be reported: do it */
      report_temperature(accessHandle, adapterNum, localHostName, &max_die, 
                          &max_board, &max_inlet, &max_outlet, &max_mem);

      /* If fanstatus should be reported: do it */
      report_fanstatus(accessHandle, adapterNum, localHostName);

      /* Note: MPSS version is part of uos version */ 
      /* Report version of uOS on the MIC card. */
      report_uosversion(accessHandle, adapterNum, localHostName);

      /* Report ECC state of memory (can be switch on and off by same SDK) */
      report_ECCstate(accessHandle, adapterNum, localHostName);

      /* Report current power usage */
      report_powerusage(accessHandle, adapterNum, localHostName,
                           &combined_power);

      /* Report the amount of active cores the MIC device has */
      report_numcores(accessHandle, adapterNum, localHostName, &num_cores,
                         &max_cores);

      /* Report memory utilization: total, free, and buffered */
      report_memory(accessHandle, adapterNum, localHostName, &total_max, 
                      &free_max, &used_min);

      // Close adapter
      closeAdapter(accessHandle);

      if (card_nr >= 0) {
         /* we selected just one card -> abort */
         break;
      }
   }
   /* report host global values */
   if (card_nr < 0) {
      report_global_temperature(localHostName, max_die, max_board, max_inlet, max_outlet, max_mem);
      report_global_powerusage(localHostName, combined_power);
      report_global_numcores(localHostName, num_cores, max_cores);
      report_global_memory(localHostName, total_max, free_max, used_min);
   }
}

static void set_load_values(const bool state) {
   show_memory_utilization         = state;
   show_die_temperature            = state;
   show_board_temperature          = state;
   show_mem_temperature            = state;
   show_inlet_temperature          = state;
   show_outlet_temperature         = state;
   show_fanstatus                  = state;
   show_powerusage                 = state;
   show_powerlimit_physical        = state;
   show_powerlimit_upper_threshold = state;
   show_powerlimit_lower_threshold = state;
   show_flash_version              = state;
   show_driver_version             = state;
   show_uos_version                = state;
   show_ecc_state                  = state;
   show_active_cores               = state;
}

void turn_load_values_off() {
   set_load_values(false);
}

void turn_load_values_on() {
   set_load_values(true);
}

bool check_and_mark(char* load_value) {
   /* remove new lines at the end */
   int i = 0;
   int len = strlen(load_value);

   if (len <= 1) {
      return true;
   }

   if (load_value[len-1] == '\n') {
      load_value[len-1] = '\0';
      len = strlen(load_value);
   }
   /* report irregular hard to detect spaces */
   for (i = 0; i < len; i++) {
      if (load_value[i] == ' ') {
         printf("Load value %s contains irregular space!\n");
         return false;
      }
   }

   if (strncmp(load_value, "memory_utilization", strlen("memory_utilization")) == 0) {
      show_memory_utilization = true;
   } else if (strncmp(load_value, "die_temperature", strlen("die_temperature")) == 0) {
      show_die_temperature = true;
   } else if (strncmp(load_value, "board_temperature", strlen("board_temperature")) == 0) {
      show_board_temperature = true;
   } else if (strncmp(load_value, "mem_temperature", strlen("mem_temperature")) == 0) {
      show_mem_temperature = true;
   } else if (strncmp(load_value, "inlet_temperature", strlen("inlet_temperature")) == 0) {
      show_inlet_temperature = true;
   } else if (strncmp(load_value, "outlet_temperature", strlen("outlet_temperature")) == 0) {
      show_outlet_temperature = true;
   } else if (strncmp(load_value, "fanstatus", strlen("fanstatus")) == 0) {
      show_fanstatus = true;
   } else if (strncmp(load_value, "powerusage", strlen("powerusage")) == 0) {
      show_powerusage = true;
   } else if (strncmp(load_value, "powerlimit_physical", strlen("powerlimit_physical")) == 0) {
      show_powerlimit_physical = true;
   } else if (strncmp(load_value, "powerlimit_upper_threshold", strlen("powerlimit_upper_threshold")) == 0) {
      show_powerlimit_upper_threshold = true;
   } else if (strncmp(load_value, "powerlimit_lower_threshold", strlen("powerlimit_lower_threshold")) == 0) {
      show_powerlimit_lower_threshold = true;
   } else if (strncmp(load_value, "flash_version", strlen("flash_version")) == 0) {
      show_flash_version = true;
   } else if (strncmp(load_value, "driver_version", strlen("driver_version")) == 0) {
      show_driver_version = true;
   } else if (strncmp(load_value, "uos_version", strlen("uos_version")) == 0) {
      show_uos_version = true;
   } else if (strncmp(load_value, "ecc_state", strlen("ecc_state")) == 0) {
      show_ecc_state = true;
   } else if (strncmp(load_value, "active_cores", strlen("active_cores")) == 0) {
      show_active_cores = true;
   } else {
      printf("Unknown load value: %s\n", load_value);
      return false;
   }
   return true;
}

void read_config_and_set_value(const char *filename) {
   FILE *config = NULL;
   char block[1024*1024];
   char *load_value = NULL;

   if (filename == NULL) {
      printf("No file name given.\n");
      exit(1);
   }

   if ((config = fopen(filename, "r")) == NULL) {
      printf("Config file not found!\n");
      exit(1);
   }

   turn_load_values_off();

   while (fgets(block, sizeof(block), config)) {
      char *context = NULL;
      /* either in new lines or space separated load values are allowed */
      if ((load_value = strtok_r(block, " \n", &context)) != NULL) {
         do {
            if (check_and_mark(load_value) != true) {
               fclose(config);
               printf("Error during parsing of config file, aborting!\n");
               exit(1);
            }
         } while ((load_value = strtok_r(NULL, " \n", &context)) != NULL);
      }
   }

   fclose(config);
}

