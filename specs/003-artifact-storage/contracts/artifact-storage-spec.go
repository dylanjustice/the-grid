// ArtifactStorageSpec is the target type for synthetics-operator/api/v1alpha1/synthetictest_types.go.
// Replace the existing one-field struct with this expanded version.
//
// Both credentialsSecret and serviceAccountAnnotations may be set;
// if both are present, IAM delegation takes precedence and a warning is logged.

type ArtifactStorageSpec struct {
	// Enabled is the feature gate. When false all other fields are ignored.
	Enabled bool `json:"enabled"`

	// Bucket is the object storage bucket name.
	// +kubebuilder:validation:MinLength=1
	Bucket string `json:"bucket,omitempty"`

	// Endpoint is the S3-compatible API endpoint URL.
	// Leave empty to use the AWS S3 default endpoint.
	// Set for MinIO (e.g. "http://minio.minio-ns.svc:9000") or GCS S3 interop
	// (e.g. "https://storage.googleapis.com").
	Endpoint string `json:"endpoint,omitempty"`

	// Region is the storage region (e.g. "us-east-2").
	// Optional for MinIO.
	Region string `json:"region,omitempty"`

	// CredentialsSecret names a Secret in the same namespace that contains
	// keys "accessKey" and "secretKey" for static credential authentication.
	// The operator does not create this Secret; it must already exist.
	CredentialsSecret string `json:"credentialsSecret,omitempty"`

	// ServiceAccountAnnotations are merged onto the workflow ServiceAccount.
	// Use {"eks.amazonaws.com/role-arn": "<arn>"} for AWS IRSA.
	// Use {"iam.gke.io/gcp-service-account": "<email>"} for GKE Workload Identity.
	// When non-empty the artifact repository uses ambient SDK credentials
	// (useSDKCreds: true); CredentialsSecret is ignored.
	ServiceAccountAnnotations map[string]string `json:"serviceAccountAnnotations,omitempty"`
}
