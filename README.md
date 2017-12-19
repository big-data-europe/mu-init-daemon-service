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

`database` must be another service defined in your `docker-compose.yml` running a triple store (e.g. [Virtuoso](https://hub.docker.com/r/tenforce/virtuoso/))


Add rules to the `dispatcher.ex` to dispatch requests to the init-daemon service. E.g. 

```
  match "/init-daemon/*path" do
    Proxy.forward conn, path, "http://initdaemon/"
  end
```

More information how to setup a mu.semte.ch project can be found in [mu-project](https://github.com/mu-semtech/mu-project).

## Using the init-daemon with the [delta-service](https://github.com/mu-semtech/mu-delta-service) and the [mu-swarm-logger-service](https://github.com/big-data-europe/mu-swarm-logger-service)
This allows you to mark a service as being observable by the init-daemon, which will figure out the status of a service through a health check.

To enable this, you need the following:
* An instance of the [delta-service](https://github.com/mu-semtech/mu-delta-service), configured to warn the init-daemon of any effective changes.
To do so, just add this `http://initdaemon/process_delta` in the subscribers.json configuration file for the delta service.

Example subscribers.json
```
{
  "potentials":[
  ],
  "effectives":[
    "http://initdaemon/process_delta"
  ]
}
```
* An instance of the [mu-swarm-logger-service](https://github.com/big-data-europe/mu-swarm-logger-service), configured to write logs through the delta-service, instead of the database directly.
```
logger:
  build: ./mu-swarm-logger-service/
  links:
    - delta:database
```
* An instance of your service, with the following configuration
In order to make it observable by the logger:
```
labels:
  - "LOG=1"
```

To specify which step is assigned to this service:
```
environment:
  INIT_DAEMON_STEP: step_1
```
You can also specify what status should be set following a healthy or an unhealthy health check.
```
environment:
  INIT_DAEMON_STEP_STATUS_WHEN_HEALTHY: done
  INIT_DAEMON_STEP_STATUS_WHEN_UNHEALTHY: failed
```

You can set whether the initdaemon should ignore the healthchecks coming from a specific service by giving that service the following environment variable:
```
environment:
  INIT_DAEMON_CHECK_HEALTH_STATUS: "false"
```

The default status for a healthy check is 'ready'.
The default status for an unhealthy check is 'failed'.
You can override this by changing the ENV variables of the init-daemon, using these names:
```
environment:
  DEFAULT_STEP_STATUS_WHEN_HEALTHY: foo
  DEFAULT_STEP_STATUS_WHEN_UNHEALTHY: bar
```

If, for any reason, the init-daemon should stop to try and verify health checks, you can just set this ENV variable to "false":
```
environment:
  CHECK_HEALTH_STATUS: false
```

