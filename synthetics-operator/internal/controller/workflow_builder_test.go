package controller

import (
	"context"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"

	gridv1alpha1 "github.com/dylanjustice/the-grid/synthetics-operator/api/v1alpha1"
)

var _ = Describe("DefaultWorkflowBuilder", func() {
	var (
		builder *DefaultWorkflowBuilder
		sa      string
		test    *gridv1alpha1.SyntheticTest
	)

	BeforeEach(func() {
		builder = &DefaultWorkflowBuilder{}
		sa = "test-sa"
		test = &gridv1alpha1.SyntheticTest{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "my-synthetic",
				Namespace: "default",
				UID:       types.UID("uid-abc"),
			},
			Spec: gridv1alpha1.SyntheticTestSpec{
				Schedule:           "*/10 * * * *",
				ServiceAccountName: &sa,
				Entrypoint:         "run",
				Source: gridv1alpha1.SyntheticTestSource{
					Inline: "import { test } from '@playwright/test'",
				},
			},
		}
	})

	Describe("BuildCronWorkflow and BuildWorkflow share identical container and volume config", func() {
		It("produces the same container image, command, name, and volume mounts for both product types", func() {
			cw, err := builder.BuildCronWorkflow(context.Background(), test)
			Expect(err).NotTo(HaveOccurred())

			wf, err := builder.BuildWorkflow(context.Background(), test)
			Expect(err).NotTo(HaveOccurred())

			cwSpec := cw.Spec.WorkflowSpec
			wfSpec := wf.Spec

			Expect(cwSpec.ServiceAccountName).To(Equal(wfSpec.ServiceAccountName))
			Expect(cwSpec.Entrypoint).To(Equal(wfSpec.Entrypoint))
			Expect(len(cwSpec.Templates)).To(Equal(len(wfSpec.Templates)))

			cwContainer := cwSpec.Templates[0].Container
			wfContainer := wfSpec.Templates[0].Container
			Expect(cwContainer.Image).To(Equal(wfContainer.Image))
			Expect(cwContainer.Command).To(Equal(wfContainer.Command))
			Expect(cwContainer.Name).To(Equal(wfContainer.Name))
			Expect(cwContainer.VolumeMounts).To(Equal(wfContainer.VolumeMounts))

			Expect(cwSpec.Volumes).To(Equal(wfSpec.Volumes))
		})
	})

	Describe("BuildWorkflow", func() {
		It("returns a *wfv1.Workflow (not a CronWorkflow) and the CronWorkflow variant carries the schedule", func() {
			wf, err := builder.BuildWorkflow(context.Background(), test)
			Expect(err).NotTo(HaveOccurred())
			Expect(wf).NotTo(BeNil())

			// The WorkflowSpec itself has no schedule field; only CronWorkflowSpec does.
			// Confirm the CronWorkflow carries the schedule while the Workflow's spec does not.
			cw, err := builder.BuildCronWorkflow(context.Background(), test)
			Expect(err).NotTo(HaveOccurred())
			Expect(cw.Spec.Schedules).NotTo(BeEmpty())
			// wf.Spec is wfv1.WorkflowSpec — the absence of Schedules is structural.
			Expect(wf.Spec.Entrypoint).To(Equal(test.Spec.Entrypoint))
		})

		It("applies container defaults when fields are empty", func() {
			wf, err := builder.BuildWorkflow(context.Background(), test)
			Expect(err).NotTo(HaveOccurred())
			c := wf.Spec.Templates[0].Container
			Expect(c.Image).To(Equal(defaultImage))
			Expect(c.Command).To(Equal(defaultCommand))
			Expect(c.Name).To(Equal(defaultName))
		})
	})

	Describe("BuildCronWorkflow", func() {
		It("sets the schedule from the SyntheticTest spec", func() {
			cw, err := builder.BuildCronWorkflow(context.Background(), test)
			Expect(err).NotTo(HaveOccurred())
			Expect(cw.Spec.Schedules).To(ConsistOf("*/10 * * * *"))
		})

		It("returns an error when schedule is empty", func() {
			test.Spec.Schedule = ""
			_, err := builder.BuildCronWorkflow(context.Background(), test)
			Expect(err).To(HaveOccurred())
		})

		It("returns an error when source inline is empty", func() {
			test.Spec.Source.Inline = ""
			_, err := builder.BuildCronWorkflow(context.Background(), test)
			Expect(err).To(HaveOccurred())
		})

		It("defaults service account name to the SyntheticTest name when nil", func() {
			test.Spec.ServiceAccountName = nil
			cw, err := builder.BuildCronWorkflow(context.Background(), test)
			Expect(err).NotTo(HaveOccurred())
			Expect(cw.Spec.WorkflowSpec.ServiceAccountName).To(Equal(test.Name))
		})

		Context("artifact storage", func() {
			It("sets ArtifactRepositoryRef when artifact storage is enabled", func() {
				test.Spec.ArtifactStorage = &gridv1alpha1.ArtifactStorageSpec{
					Enabled: true,
					Bucket:  "my-bucket",
				}
				cw, err := builder.BuildCronWorkflow(context.Background(), test)
				Expect(err).NotTo(HaveOccurred())
				ref := cw.Spec.WorkflowSpec.ArtifactRepositoryRef
				Expect(ref).NotTo(BeNil())
				Expect(ref.ConfigMap).To(Equal(test.Name + "-artifact-repository"))
				Expect(ref.Key).To(Equal("default"))
			})

			It("declares the playwright-report output artifact when enabled", func() {
				test.Spec.ArtifactStorage = &gridv1alpha1.ArtifactStorageSpec{
					Enabled: true,
					Bucket:  "my-bucket",
				}
				cw, err := builder.BuildCronWorkflow(context.Background(), test)
				Expect(err).NotTo(HaveOccurred())
				tmpl := cw.Spec.WorkflowSpec.Templates[0]
				Expect(tmpl.Outputs.Artifacts).To(HaveLen(1))
				Expect(tmpl.Outputs.Artifacts[0].Name).To(Equal("playwright-report"))
				Expect(tmpl.Outputs.Artifacts[0].Path).To(Equal("/app/playwright-report"))
			})

			It("leaves ArtifactRepositoryRef nil when artifact storage is disabled", func() {
				cw, err := builder.BuildCronWorkflow(context.Background(), test)
				Expect(err).NotTo(HaveOccurred())
				Expect(cw.Spec.WorkflowSpec.ArtifactRepositoryRef).To(BeNil())
			})

			It("leaves ArtifactRepositoryRef nil when ArtifactStorage spec is nil", func() {
				test.Spec.ArtifactStorage = nil
				cw, err := builder.BuildCronWorkflow(context.Background(), test)
				Expect(err).NotTo(HaveOccurred())
				Expect(cw.Spec.WorkflowSpec.ArtifactRepositoryRef).To(BeNil())
			})
		})
	})
})
