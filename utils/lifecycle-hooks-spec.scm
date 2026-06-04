; Fixture spec for test-lifecycle-hooks.sh. Defines a class with both
; after-copy and after-destroy hooks; the test verifies that gen-ctl-io
; emits the corresponding extern declarations and call sites.

(define-class hooked no-parent
  (define-property name "" 'string)
  (after-copy hook_after_copy)
  (after-destroy hook_after_destroy))
