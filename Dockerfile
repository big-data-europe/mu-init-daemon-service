FROM semtech/mu-ruby-template:1.3.1-ruby2.1

MAINTAINER Erika Pauwels <erika.pauwels@gmail.com>
MAINTAINER Aad Versteden <madnificent@gmail.com>

ENV CHECK_HEALTH_STATUS false
ENV HEALTH_STATUS_VALUE healthy
ENV CHECK_ONLY_LATEST_HEALTHCHECK false
ENV DEFAULT_STEP_STATUS_WHEN_SUCCESSFUL ready
# ONBUILD of mu-ruby-template takes care of everything