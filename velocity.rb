require 'terminal-table'

def main
  rows = []
  rows << ['Weeks Ago', 'Estimation Velocity', 'Estimated [d]', 'Spent [d]', 'Project Velocity', 'Estimated Features [d]', 'Total Spent [d]']
  rows << :separator

  [24, 18, 12, 9, 6, 3, 2, 1].each do |months|
    rows << calculate_velocity(months * 4, months * 4)
  end

  weeks = 10
  weeks.downto(0) do |weeks_ago|
    rows << calculate_velocity(weeks_ago)
  end

  table = Terminal::Table.new rows: rows, title: 'Renuo Velocity'
  rows.each_index { |index| table.align_column(index, :right) }

  puts table
end

def format_days(hours)
  (hours / 8.5).round(1)
end

def calculate_velocity(weeks_ago, total_weeks = 1)
  weekly_planning_estimated_hours, weekly_planning_spent_hours, estimated_feature_hours, spent_hours = calculate_estimated_and_spent(weeks_ago, total_weeks)

  weeks_ago_display = total_weeks == 1 ? "Sprint #{weeks_ago} weeks ago" : "Last #{total_weeks / 4} months"
  weekly_planning_velocity = weekly_planning_spent_hours.zero? ? 0 : weekly_planning_estimated_hours / weekly_planning_spent_hours
  total_project_velocity = spent_hours.zero? ? 0 : estimated_feature_hours / spent_hours


  return weeks_ago_display,
    weekly_planning_velocity.round(3), format_days(weekly_planning_estimated_hours), format_days(weekly_planning_spent_hours),
    total_project_velocity.round(3), format_days(estimated_feature_hours), format_days(spent_hours)
end

def calculate_estimated_and_spent(weeks_ago, total_weeks)
  now = DateTime.now
  @start_date = now - now.wday.days - weeks_ago.weeks
  @end_date = @start_date + total_weeks.weeks

  user_ids = [1, 2, 25, 26, 30, 31]
  ignore_issues = [3646]

  issues_this_week = TimeEntry.where(spent_on: @start_date..@end_date, user_id: user_ids).includes(:issue).map(&:issue).uniq.reject do |i|
    i.nil? || ignore_issues.include?(i.id) || !i.closed?
  end
  ongoing = IssueCustomField.find(8)
  sprint = IssueCustomField.find(7)
  issues_this_week_enhanced = issues_this_week.map { |v|
    {
      ongoing: v.custom_field_value(ongoing) == '1',
      sprint: v.custom_field_value(sprint).try(:to_date),
      issue: v,
      tracker_name: v.tracker.name,
      estimated_and_spent: !v.estimated_hours.to_f.zero? && !v.spent_hours.to_f.zero?
    }
  }
  normal_issues = issues_this_week_enhanced.select { |v| !v[:ongoing] }

  weekly_planning_estimated_hours = normal_issues.select { |v| v[:estimated_and_spent] }.map { |i| i[:issue] }.map(&:estimated_hours).reduce(:+).to_f
  weekly_planning_spent_hours = normal_issues.select { |v| v[:estimated_and_spent] }.map { |i| i[:issue] }.map(&:spent_hours).reduce(:+).to_f

  estimated_feature_hours = normal_issues.select { |v| v[:estimated_and_spent] }.select { |v| v[:tracker_name] == 'Feature' }.map { |i| i[:issue] }.map(&:estimated_hours).reduce(:+).to_f
  spent_hours = normal_issues.select { |v| v[:estimated_and_spent] }.map { |i| i[:issue] }.map(&:spent_hours).reduce(:+).to_f

  return weekly_planning_estimated_hours, weekly_planning_spent_hours, estimated_feature_hours, spent_hours
end

main()
