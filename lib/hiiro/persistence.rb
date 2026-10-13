# Loaded through Hiiro's autoload of DB or any persistent model: connects,
# defines every model, creates or upgrades their tables, then starts the runtime.
require_relative 'db'

Hiiro::DB.connection
Sequel::Model.require_valid_table = false

%w[invocation link capture branch check_run tags task_record app_record assignment todo
   pinned_pr pr_monitor_checkpoint project pane_home pin_record reminder registry job schedule picker_exclusion].each { |model| require_relative model }

Hiiro::DB.setup!
Hiiro::Runtime.started!
