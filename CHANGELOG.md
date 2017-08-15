## 3.0.2
  - Fix some documentation issues

# 3.0.0
  - Breaking: depend on logstash-core-plugin-api between 1.60 and 2.99

# 2.0.5
  - Depend on logstash-core-plugin-api instead of logstash-core, removing the need to mass update plugins on major releases of logstash
# 2.0.4
  - New dependency requirements for logstash-core for the 5.0 release
## 2.0.2
 - Update the test to play nice within the context of the default
   plugins LS core integration test.

## 2.0.0
 - Plugins were updated to follow the new shutdown semantic, this mainly allows Logstash to instruct input plugins to terminate gracefully, 
   instead of using Thread.raise on the plugins' threads. Ref: https://github.com/elastic/logstash/pull/3895
 - Dependency on logstash-core update to 2.0

# 0.2.0
 - Add support for using RELP over SSL sockets
