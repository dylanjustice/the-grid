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

	corev1 "k8s.io/api/core/v1"
	v1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	wfv1 "github.com/argoproj/argo-workflows/v3/pkg/apis/workflow/v1alpha1"
	gridv1alpha1 "github.com/dylanjustice/the-grid/synthetics-operator/api/v1alpha1"
)

// SyntheticTestReconciler reconciles a SyntheticTest object
type SyntheticTestReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=thegrid.io,resources=synthetictests,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=thegrid.io,resources=synthetictests/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=thegrid.io,resources=synthetictests/finalizers,verbs=update
// +kubebuilder:rbac:groups="",resources=configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=serviceaccounts,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=rbac.authorization.k8s.io,resources=roles,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=rbac.authorization.k8s.io,resources=rolebindings,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=argoproj.io,resources=cronworkflows,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=argoproj.io,resources=workflowtaskresults,verbs=create;patch

func (r *SyntheticTestReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = logf.FromContext(ctx)

	syntheticTest := &gridv1alpha1.SyntheticTest{}
	if err := r.Get(ctx, req.NamespacedName, syntheticTest); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	configMapName := syntheticTest.Name + "-config"
	configMap := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      configMapName,
			Namespace: syntheticTest.Namespace,
		},
		Data: map[string]string{
			"test.spec.ts": syntheticTest.Spec.Source.Inline,
		},
	}

	if err := r.Create(ctx, configMap); err != nil && !errors.IsAlreadyExists(err) {
		return ctrl.Result{}, err
	}

	serviceAccount := &v1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{
			Name:      *syntheticTest.Spec.ServiceAccountName,
			Namespace: syntheticTest.Namespace,
		},
	}

	if err := r.Create(ctx, serviceAccount); err != nil && !errors.IsAlreadyExists(err) {
		return ctrl.Result{}, err
	}

	role := &rbacv1.Role{
		ObjectMeta: metav1.ObjectMeta{
			Name:      syntheticTest.Name,
			Namespace: syntheticTest.Namespace,
		},
		Rules: []rbacv1.PolicyRule{
			{
				APIGroups: []string{"argoproj.io"},
				Resources: []string{"workflowtaskresults"},
				Verbs:     []string{"create", "patch"},
			},
		},
	}

	if err := r.Create(ctx, role); err != nil && !errors.IsAlreadyExists(err) {
		return ctrl.Result{}, err
	}

	rb := &rbacv1.RoleBinding{
		ObjectMeta: metav1.ObjectMeta{
			Name:      syntheticTest.Name,
			Namespace: syntheticTest.Namespace,
		},
		RoleRef: rbacv1.RoleRef{
			APIGroup: "rbac.authorization.k8s.io",
			Kind:     "Role",
			Name:     syntheticTest.Name,
		},
		Subjects: []rbacv1.Subject{
			{
				Kind:      "ServiceAccount",
				Name:      *syntheticTest.Spec.ServiceAccountName,
				Namespace: syntheticTest.Namespace,
			},
		},
	}

	if err := r.Create(ctx, rb); err != nil && !errors.IsAlreadyExists(err) {
		return ctrl.Result{}, err
	}

	container := syntheticTest.Spec.Container
	if container.Image == "" {
		container.Image = "393657359434.dkr.ecr.us-east-2.amazonaws.com/flynn/playwright-runner-js:latest"
	}
	if len(container.Command) == 0 {
		container.Command = []string{"npx", "playwright", "test"}
	}
	if container.Name == "" {
		container.Name = "playwright"
	}
	container.VolumeMounts = append(container.VolumeMounts, corev1.VolumeMount{
		Name:      syntheticTest.Name + "-source",
		MountPath: "/app/tests",
	})

	template := wfv1.Template{
		Name:      "run",
		Container: &container,
	}

	workflow := &wfv1.CronWorkflow{
		ObjectMeta: metav1.ObjectMeta{
			Name:      syntheticTest.Name,
			Namespace: syntheticTest.Namespace,
			Labels: map[string]string{
				"the-grid.io/synthetic-test": syntheticTest.Name,
			},
		},
		Spec: wfv1.CronWorkflowSpec{
			Schedules: []string{
				syntheticTest.Spec.Schedule,
			},
			WorkflowSpec: wfv1.WorkflowSpec{
				ServiceAccountName: *syntheticTest.Spec.ServiceAccountName,
				Entrypoint:         syntheticTest.Spec.Entrypoint,
				Templates: []wfv1.Template{
					template,
				},
				Volumes: []corev1.Volume{
					{
						Name: syntheticTest.Name + "-source",
						VolumeSource: corev1.VolumeSource{
							ConfigMap: &corev1.ConfigMapVolumeSource{
								LocalObjectReference: corev1.LocalObjectReference{
									Name: configMapName,
								},
							},
						},
					},
				},
			},
		},
	}

	if err := r.Create(ctx, workflow); err != nil && !errors.IsAlreadyExists(err) {
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *SyntheticTestReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&gridv1alpha1.SyntheticTest{}).
		Named("synthetictest").
		Complete(r)
}
