@test "evaluate tns app status" {
  run bash -c "kubectl get pods -n $NAMESPACE -o wide | grep 'app'"
  [[ "${output}" =~ "Running" ]]
}

@test "evaluate tns db status" {
  run bash -c "kubectl get pods -n $NAMESPACE -o wide | grep 'db'"
  [[ "${output}" =~ "Running" ]]
}

@test "evaluate tns loadgen status" {
  run bash -c "kubectl get pods -n $NAMESPACE -o wide | grep 'loadgen'"
  [[ "${output}" =~ "Running" ]]
}

@test "evaluate tns ingress status" {
  run bash -c "curl 'http://${HOSTNAME}' | grep 'Grafana News'"
  [[ "${output}" =~ 'Grafana News' ]]
}
