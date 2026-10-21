// Package controller — design contract for WorkflowBuilder.
//
// This file is a specification artifact, not compilable production code.
// It captures the interface shape and expected behavior before implementation.

package controller

import (
	"context"

	wfv1 "github.com/argoproj/argo-workflows/v3/pkg/apis/workflow/v1alpha1"
	gridv1alpha1 "github.com/dylanjustice/the-grid/synthetics-operator/api/v1alpha1"
)

// WorkflowBuilder inflates a SyntheticTest into Argo workflow objects.
// The interface is the seam between the reconciler (caller) and all
// knowledge of Argo's field layout (implementation).
//
// Both methods must be safe to call concurrently on the same instance.
type WorkflowBuilder interface {
	// BuildCronWorkflow returns a fully-formed CronWorkflow ready to be
	// applied to the cluster. The returned workflow has a schedule derived
	// from test.Spec.Schedule and all defaulting applied.
	//
	// Errors:
	//   - test.Spec.Schedule is empty
	//   - test.Spec.Source.Inline is empty
	//   - test.Spec.ServiceAccountName is nil
	BuildCronWorkflow(ctx context.Context, test *gridv1alpha1.SyntheticTest) (*wfv1.CronWorkflow, error)

	// BuildWorkflow returns a fully-formed one-shot Workflow with the same
	// container spec, volumes, and service account as BuildCronWorkflow
	// but no schedule. Intended for on-demand and event-driven execution.
	//
	// Errors:
	//   - test.Spec.Source.Inline is empty
	//   - test.Spec.ServiceAccountName is nil
	BuildWorkflow(ctx context.Context, test *gridv1alpha1.SyntheticTest) (*wfv1.Workflow, error)
}

// SyntheticTestReconciler (modified shape — fields added)
//
// type SyntheticTestReconciler struct {
//     client.Client
//     Scheme          *runtime.Scheme
//     WorkflowBuilder WorkflowBuilder   // <-- injected at startup
// }

// DefaultWorkflowBuilder is the production implementation.
// Zero-value is ready to use; no initialization required.
//
// type DefaultWorkflowBuilder struct{}
//
// func (b *DefaultWorkflowBuilder) BuildCronWorkflow(...) (*wfv1.CronWorkflow, error) { ... }
// func (b *DefaultWorkflowBuilder) BuildWorkflow(...)    (*wfv1.Workflow, error)       { ... }

// FakeWorkflowBuilder is the test implementation (defined in _test.go files).
//
// type FakeWorkflowBuilder struct {
//     BuildCronWorkflowCalled bool
//     BuildWorkflowCalled     bool
//     ReceivedTest            *gridv1alpha1.SyntheticTest
//     CronWorkflowResult      *wfv1.CronWorkflow
//     WorkflowResult          *wfv1.Workflow
//     Err                     error
// }

// Wiring in cmd/main.go:
//
// if err := (&controller.SyntheticTestReconciler{
//     Client:          mgr.GetClient(),
//     Scheme:          mgr.GetScheme(),
//     WorkflowBuilder: &controller.DefaultWorkflowBuilder{},
// }).SetupWithManager(mgr); err != nil { ... }
