# Init service microservice
Microservice to report the progress of a service's initialization process.

## Available requests

#### GET /canStart
Validate if a given step (specified by its code) of a pipeline can be started. The step is specified through the step query param. Returns `"true"` or `"false"` as `text/plain` on success.

_E.g. /canStart?step="hdfs_init"_

#### PUT /execute
Start the execution of a step in a pipeline. The step is specified through the step query param. Returns `204` on success.

_E.g. /execute?step="hdfs_init"_

#### PUT /finish
Finish the execution of a step in a pipeline. The step is specified through the step query param. Returns `204` on success.

_E.g. /finish?step="hdfs_init"_


## Integrate init-daemon service in a mu.semte.ch project
Add the following snippet to your `docker-compose.yml` to include the init-daemon service in your project.

```
initdaemon:
  image: bde2020/init-daemon-service
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
