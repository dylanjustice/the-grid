/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controller

import (
	"context"

	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	wfv1 "github.com/argoproj/argo-workflows/v3/pkg/apis/workflow/v1alpha1"
	gridv1alpha1 "github.com/dylanjustice/the-grid/synthetics-operator/api/v1alpha1"
)

// SyntheticTestRunReconciler reconciles a SyntheticTestRun object
type SyntheticTestRunReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=thegrid.io,resources=synthetictestruns,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=thegrid.io,resources=synthetictestruns/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=thegrid.io,resources=synthetictestruns/finalizers,verbs=update
// +kubebuilder:rbac:groups=argoproj.io,resources=workflows,verbs=get;list;watch
func (r *SyntheticTestRunReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	workflow := &wfv1.Workflow{}
	if err := r.Get(ctx, req.NamespacedName, workflow); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	if !workflow.Status.Phase.Completed() {
		return ctrl.Result{}, nil
	}

	testName := workflow.Labels["the-grid.io/synthetic-test"]

	run := &gridv1alpha1.SyntheticTestRun{
		ObjectMeta: metav1.ObjectMeta{
			Name:      workflow.Name,
			Namespace: workflow.Namespace,
		},
		Spec: gridv1alpha1.SyntheticTestRunSpec{
			Name:         testName,
			WorkflowName: workflow.Name,
			StartedAt:    &workflow.Status.StartedAt,
		},
	}

	if err := r.Create(ctx, run); err != nil && !errors.IsAlreadyExists(err) {
		return ctrl.Result{}, err
	}

	log.Info("created SyntheticTestRun", "workflow", workflow.Name, "phase", workflow.Status.Phase)
	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *SyntheticTestRunReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&wfv1.Workflow{}, builder.WithPredicates(
			predicate.NewPredicateFuncs(
				func(object client.Object) bool {
					labels := object.GetLabels()
					_, ok := labels["the-grid.io/synthetic-test"]
					return ok
				},
			),
		)).
		Named("synthetictestrun").
		Complete(r)
}
