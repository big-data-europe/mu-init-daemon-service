# Init service microservice
Microservice to report the progress of a service's initialization process.

## Available requests
Indication of the state can happen in two main ways.  The first way describes processes which finish, the second describes processes which may keep running forever.

### Types of processes and their states
Processes which finish generally have the following states:

- not_started
- starting (see /boot)
- running  (see /execute)
- done (see /finish)

Processes which accept requests tend to have the following states:

- not_started
- starting (see /boot)
- ready (see /ready)

All processes may end in a 'failed' state, which locks further steps to start automatically.  See /fail.

### Overview of available calls

#### GET /canStart
Validate if a given step (specified by its code) of a pipeline can be started. The step is specified through the step query param. Returns `"true"` or `"false"` as `text/plain` on success.

_E.g. /canStart?step="hdfs_init"_

#### PUT /boot
Starts the booting of a step in the pipeline.  The step is specified through the step query param. Returns `204` on success.

_E.g. /boot?step="hdfs_init"_

#### PUT /execute
Start the execution of a step in a pipeline. The step is specified through the step query param. Returns `204` on success.

_E.g. /execute?step="hdfs_init"_

#### PUT /finish
Finish the execution of a step in a pipeline. The step is specified through the step query param. Returns `204` on success.

_E.g. /finish?step="hdfs_init"_

#### PUT /ready
Indicates a component is ready to accept requests in a pipeline. The step is specified through the step query param. Returns `204` on success.

_E.g. /ready?step="hdfs_init"_

#### PUT /fail
Indicates a component failed. The step is specified through the step query param. Returns `204` on success.

_E.g. /fail?step="hdfs_init"_


## Integrate init-daemon service in a mu.semte.ch project
Add the following snippet to your `docker-compose.yml` to include the init-daemon service in your project.

```
initdaemon:
  image: bde2020/mu-init-daemon-service
  links:
    - database:database
```

Environment variables can be provided to change the behavior of the service.
```
CHECK_HEALTH_STATUS : Whether the microservice should try to discover the status of a step by analyzing the docker logs. Defaults to "false".
HEALTH_STATUS_VALUE : The value the microservice should compare against for the health check . Defaults to "healthy".
CHECK_ONLY_LATEST_HEALTHCHECK : Whether the microservice should only check the latest log for the specified step. Otherwise, it checks if, at any point, the container was in a state HEALTH_STATUS_VALUE. Defaults to "false".
```

`database` must be another service defined in your `docker-compose.yml` running a triple store (e.g. [Virtuoso](https://hub.docker.com/r/tenforce/virtuoso/))


Add rules to the `dispatcher.ex` to dispatch requests to the init-daemon service. E.g. 

```
  match "/init-daemon/*path" do
    Proxy.forward conn, path, "http://initdaemon/"
  end
```

More information how to setup a mu.semte.ch project can be found in [mu-project](https://github.com/mu-semtech/mu-project).
