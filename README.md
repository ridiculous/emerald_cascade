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

- `EmeraldCascade::AttachmentUploads` - generic `create`/`destroy` for a submission's attachment
  collection (optional max count, append, after-create hook, redirect back). The host supplies
  `attachments`, `attachment_limit`, `attachments_redirect_url`, `after_attachment_created`.

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

Engine behavior is exercised from the host suite:

- `spec/emerald_cascade/generic_form_spec.rb` - **genericness proof / boundary guard**: a second,
  unrelated form built entirely through the public API against a throwaway table. If any engine
  code became coupled to the closing form, this fails.
- The closing-form specs (`spec/models/closing_form*`, `spec/features/closing_form/*`,
  `spec/requests/admin/closing_form_submissions_js_spec.rb`) are the end-to-end regression net.

## Local development (standalone)

The engine is self-contained and can be developed on its own, without the host app. It ships a
minimal dummy Rails app (`spec/dummy`, in-memory SQLite) so the suite boots the engine exactly
as a real host would:

```
cd engines/emerald_cascade
bundle install
bundle exec rake        # runs rspec + rubocop
```

`spec/emerald_cascade/submittable_spec.rb` is the standalone smoke test. Everything needed to
extract the engine into its own repository is already here: `gemspec`, `Gemfile`, `Rakefile`,
`LICENSE`, `.rubocop.yml`, and a CI workflow (`.github/workflows/ci.yml`). The only remaining
step at move time is to point the host's `Gemfile` at the new source (a git or version
requirement) instead of `path: 'engines/emerald_cascade'`.
