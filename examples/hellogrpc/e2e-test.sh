#!/bin/bash -e

# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

LANGUAGE="$1"

function get_lb_ip() {
    kubectl --namespace=${USER} get service hello-grpc-staging \
	-o jsonpath='{.status.loadBalancer.ingress[0].ip}'
}

function create() {
   bazel run examples/hellogrpc/${LANGUAGE}/server:staging.create
}

function check_msg() {
   bazel build examples/hellogrpc/${LANGUAGE}/client

   OUTPUT=$(./bazel-bin/examples/hellogrpc/${LANGUAGE}/client/client $(get_lb_ip))
   echo Checking response from service: "${OUTPUT}" matches: "DEMO$1<space>"
   echo "${OUTPUT}" | grep "DEMO$1[ ]"
}

function edit() {
   ./examples/hellogrpc/${LANGUAGE}/server/edit.sh "$1"
}

function update() {
   bazel run examples/hellogrpc/${LANGUAGE}/server:staging.replace
}

function delete() {
   bazel run examples/hellogrpc/${LANGUAGE}/server:staging.describe
   bazel run examples/hellogrpc/${LANGUAGE}/server:staging.delete
}


create
trap "delete" EXIT
sleep 25
check_msg

for i in $RANDOM $RANDOM; do
  edit "$i"
  update
  # Don't let K8s slowness cause flakes.
  sleep 25
  check_msg "$i"
done

# Replace the trap with a success message.
trap "delete; echo PASS" EXIT
