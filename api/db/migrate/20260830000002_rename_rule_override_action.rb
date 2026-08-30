class RenameRuleOverrideAction < ActiveRecord::Migration[8.1]
  def change
    rename_column :rule_overrides, :action, :override_action   # "action" colide com params[:action] do Rails
  end
end
