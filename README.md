# EmeraldCascade

A mountable Rails engine for **definition-driven, resumable multi-step forms** (think a
self-hosted Typeform). It is **storage-agnostic**: the engine owns no database tables and no
answer columns. A host app declares a form, mixes the engine's concerns into its own models
and controllers, and keeps full control of how answers are persisted.

The name nods to Seattle: *Emerald* City + the *Cascade* range (a multi-step flow).

The **closing form** (`app/models/closing_form/`, `app/controllers/closing_form/`,
`app/models/closing_form_submission.rb`) is the reference implementation in this app.

## Philosophy / boundary

- **Host owns storage.** The engine reads and writes answers through the host model's normal
  attribute API (wide columns, JSONB, whatever). No migrations ship with the engine.
- **One source of truth.** A `Definition` declares the pages, fields, per-record visibility,
  permitted params, and validations. Controllers, views, strong params, and the state machine
  all derive from it, so they can't drift.
- **Concerns, not inheritance.** Behavior is delivered as `ActiveSupport::Concern`s and
  controller concerns, so host models/controllers keep their own base classes (e.g.
  `ApplicationRecord`, `Spree::Admin::BaseController`).
- **Host override seams.** Generic views live in the engine; the host overrides any of them by
  defining a same-path partial (Rails view-path precedence), and overrides controller behavior
  via small documented hook methods.

## Building blocks

### Definition / Step / Field (POROs)

```ruby
class ClosingForm::Definition < EmeraldCascade::Definition
  step :name, title: 'What is your name?', fields: [
    EmeraldCascade::Field.new(:full_name, type: :string, required: true)
  ]
  step :photos, title: 'Packing sheet photos', partial: 'photos',
       visible_when: ->(s) { s.photos_step? }
  step :review, title: 'Review & submit', partial: 'review'
end
```

- Steps are kept in declaration order; `visible_when` only *omits* a page for some records.
- `Definition.field_param_keys` returns the flat strong-params shape for every field.
- `Definition.for(record)` / `visible_step_keys(record)` return the visible subset.

**Field types:** `:string`, `:text`, `:boolean`, `:enum`, `:integer`, `:decimal`, `:array`
(checklist), `:rating` (stars). `:enum`/`:array`/`:rating` take `choices:`. A field can be
`required:` (a bool or a `->(record)` predicate).

**Conditional (companion) fields** via `depends_on`:

```ruby
EmeraldCascade::Field.new(:issue_details, type: :text,
                          depends_on: { field: :had_issues, equals: true })   # exact match
EmeraldCascade::Field.new(:which_items, type: :array, choices: %w[a b],
                          depends_on: { field: :flags, includes: 'a' })       # array contains
```

A companion defaults to required-when-shown; it is hidden (and skipped by validation) until its
controlling answer matches. The same `depends_on` drives the client-side show/hide.

### `EmeraldCascade::Submittable` (model concern)

Mix into any model with a string `state` column to get a resumable, definition-driven page
lifecycle:

```ruby
class ClosingFormSubmission < ApplicationRecord
  include EmeraldCascade::Submittable
  emerald_cascade_form ClosingForm::Definition
end
```

- **States**: `not_started`, every step key (the ordered superset), `complete`, `locked`.
- **Events**: `start`, `advance`, `back`, `submit`, `reopen`, `lock`.
- **Navigation helpers** translate the persisted `state` (a superset page) to the per-record
  *visible* subset: `visible_steps`, `visible_page_keys`, `next_page_of` / `prev_page_of`,
  `begin_flow!`, `advance_from!`, `goto_page!`, etc.
- **Completion hooks** (host no-ops to override): `emerald_cascade_before_complete` and
  `emerald_cascade_after_complete` run inside the `submit` transition; `completed_at` is stamped
  automatically when the column exists.

### `EmeraldCascade::Attachable` (model concern)

Maps a generic background-processing lifecycle onto the host's own columns (status + result),
with per-parent append-order position:

```ruby
class ClosingFormPhoto < ApplicationRecord
  include EmeraldCascade::Attachable
  emerald_cascade_attachable status: :ocr_status, result: :ocr_result,
                             processor: 'PackingSheetOcrProcessor',
                             position_scope: :closing_form_submission_id,
                             rescue_from: PackingSheetOcr::Parser::Error, status_prefix: :ocr
end
```

- `process_async!` enqueues `EmeraldCascade::ProcessAttachmentJob`; `emerald_cascade_process!`
  runs the host processor (`#call(record) => result`) and records success/soft-failure.
- `.processing_state(records)` rolls a set up to `:reading` / `:failed` / `:done` / `nil`.
- Generic aliases `processing_status` / `processing_result` read the mapped columns.

### `EmeraldCascade::LineItemGroup` (model concern)

Centralizes the operator-editable columns of a nested/repeating group and derives strong params:

```ruby
class ClosingFormItem < ApplicationRecord
  include EmeraldCascade::LineItemGroup
  emerald_cascade_line_item :pickup_pans, :leftover_pans, :fully_consumed
end

ClosingFormItem.nested_attributes_params(extra: [:runout], allow_destroy: true)
# => [:id, :_destroy, :pickup_pans, :leftover_pans, :fully_consumed, :runout]
```

### Controller concerns

The multi-step *flow* is driven by the engine; the host controllers supply only their record
lookup, route helpers and a few page-specific hooks.

- `EmeraldCascade::Flow` - shared base: the `@submission` guards (`require_submission`,
  `require_editable!`, `lazy_lock`) and the `current_step` lookup. The host sets `@submission` in
  a before_action and defines its routes (`submission_url`, `step_url_for(step)`). Include it in
  the host's base controller.
- `EmeraldCascade::StepFlow` - one page at a time: `show`/`update`, per-page save + validate
  (`valid_page?`), advance, and the review-page submit (`valid_for_submit?`). Host hooks:
  `on_step_show(step)`, `assign_step_attributes(step)` (call `super` to add nested params),
  `review_step_key` (default `'review'`), `submit_notice`.
- `EmeraldCascade::SubmissionFlow` - welcome-screen lifecycle: `show`, `create` (Start), `reopen`
  (Edit) and `reset` (discard). Host hook: `build_submission` (build the new record with its
  source/type/defaults).
- `EmeraldCascade::AttachmentUploads` - generic `create`/`destroy` for a submission's attachment
  collection (optional max count, append, after-create hook, redirect back). The host supplies
  `attachments`, `attachment_limit`, `attachments_redirect_url`, `after_attachment_created`.

```ruby
class ClosingForm::BaseController < ApplicationController
  include EmeraldCascade::Flow
  before_action :load_submission   # sets @submission (host-owned lookup)
  def submission_url = closing_form_submission_path(...)
  def step_url_for(step) = closing_form_step_path(step:, ...)
end

class ClosingForm::StepsController < ClosingForm::BaseController
  include EmeraldCascade::StepFlow

  def on_step_show(step) = @submission.build_product_items_from_order! if step.key == 'products'
  def assign_step_attributes(step)
    super
    @submission.assign_attributes(product_params) if step.key == 'products'
  end
end
```

Host contract: the submission model includes `Submittable` and also answers `editable?`,
`valid_page?(key)` and `valid_for_submit?`. Validation stays host-owned because a page may
validate nested records, not just its own fields.

Admin CRUD (index/edit/update) is intentionally *not* in the engine: it's ordinary Rails admin
plumbing bound to the host's stack (its admin base controller, authorization, search, pagination
and routes), not to the form builder. Hosts write a normal controller and keep its permit list in
sync with the fields via `Definition.field_param_keys` and `LineItemGroup.nested_attributes_params`.

### Views + theming

Generic rendering lives under `app/views/emerald_cascade/`:

- `steps/_fields`, `steps/_field` - render a step's fields by type.
- `steps/_field_toggle_script` - client-side companion show/hide (reads `data-emerald-show-*`,
  toggles `.emerald-show`, disables collapsed inputs). Pass the form's param `scope`.
- `attachments/_poll_script` - a Turbo-frame self-poller while a `poll_marker` is present.

Markup uses the `emerald-*` CSS class prefix and `data-emerald-*` data attributes. The host owns
the layout, CSS, and asset pipeline: it renders these partials from its own views/layout (see
`app/views/layouts/closing_form_v3.html.erb`) and can override any engine partial by defining a
same-path file (Rails view-path precedence).

## Testing

The engine is self-contained and tests itself against a minimal dummy Rails app (`spec/dummy`,
in-memory SQLite) that boots the engine exactly as a real host would:

```
bundle install
bundle exec rake        # runs rspec + rubocop
```

- `spec/emerald_cascade/generic_form_spec.rb` - **genericness proof / boundary guard**: a second,
  unrelated form built entirely through the public API against a throwaway table. If any engine
  code became coupled to a specific host form, this fails.
- `spec/emerald_cascade/submittable_spec.rb` - standalone smoke test of the state machine +
  navigation.

The engine's controllers and views are additionally exercised end-to-end by the host app's
closing-form suite (`spec/features/closing_form/*`, `spec/requests/closing_form/*`).
