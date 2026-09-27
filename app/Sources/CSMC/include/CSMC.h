#ifndef DRAFT_SMC_H
#define DRAFT_SMC_H
#include <stdint.h>
#include <stddef.h>
// Up to ten fans can each need 3s arbitration + 5s retries, plus rollback.
// EOF still reports helper death immediately; only a live firmware operation waits.
#define GUST_SET_REPLY_TIMEOUT_SECONDS 120
typedef struct { uint32_t type; uint32_t size; uint8_t bytes[32]; } GustValue;
int gust_smc_open(uint32_t *connection);
void gust_smc_close(uint32_t connection);
int gust_smc_read(uint32_t connection, const char *key, GustValue *value);
int gust_smc_write(uint32_t connection, const char *key, const GustValue *value);
int gust_server_open(uint32_t uid, int pid);
int gust_server_next(int server, uint32_t uid, int pid, char *buffer, size_t size);
void gust_server_reply(int client, const char *reply);
void gust_server_close(int server, uint32_t uid, int pid);
int gust_request(uint32_t uid, int pid, const char *command, char *reply, size_t size);
void gust_signals_install(void);
int gust_stopping(void);
double gust_uptime(void);
#endif
