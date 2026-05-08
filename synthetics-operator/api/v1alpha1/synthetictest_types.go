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

package v1alpha1

import (
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type SyntheticTestSource struct {
	Inline string `json:"inline,omitempty"`
}

type SyntheticTestSpec struct {
	Schedule           string              `json:"schedule,omitempty"`
	Source             SyntheticTestSource `json:"source,omitempty"`
	ServiceAccountName *string             `json:"serviceAccountName,omitempty"`
	Entrypoint         string              `json:"entrypoint,omitempty"`
	Container          v1.Container        `json:"container,omitempty"`
}

// SyntheticTestStatus defines the observed state of SyntheticTest.
type SyntheticTestStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// SyntheticTest is the Schema for the synthetictests API.
type SyntheticTest struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   SyntheticTestSpec   `json:"spec,omitempty"`
	Status SyntheticTestStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// SyntheticTestList contains a list of SyntheticTest.
type SyntheticTestList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []SyntheticTest `json:"items"`
}

func init() {
	SchemeBuilder.Register(&SyntheticTest{}, &SyntheticTestList{})
}
