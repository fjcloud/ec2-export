# Kubernetes/OpenShift YAML Configurations

This directory contains Kustomize configurations for deploying VM migration operators on OpenShift.

## Structure

### operators/
Contains operator installations (namespaces, operatorgroups, subscriptions)
- CNV (Container Native Virtualization) operator
- MTV (Migration Toolkit for Virtualization) operator

### custom-resources/
Contains custom resources that depend on CRDs created by operators
- HyperConverged (CNV)
- ForkliftController (MTV)

### cnv/ and mtv/
Individual component YAML files referenced by the above kustomizations

## Usage

### 1. Deploy Operators
```bash
oc apply -k yaml/operators/
```

### 2. Verify CRDs are Created
```bash
oc get crd hyperconvergeds.hco.kubevirt.io
oc get crd forkliftcontrollers.forklift.konveyor.io
```

### 3. Deploy Custom Resources
```bash
oc apply -k yaml/custom-resources/
```

## Verification

```bash
# Check CNV installation
oc get hyperconverged -n openshift-cnv

# Check MTV installation  
oc get forkliftcontroller -n openshift-mtv
```

## Prerequisites

- OpenShift 4.12+ cluster
- Cluster admin permissions
- `oc` CLI tool installed 