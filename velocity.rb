require 'terminal-table'

def main
  rows = []
  rows << ['Weeks Ago', 'Estimation Velocity', 'Estimated [d]', 'Spent [d]', 'Project Velocity', 'Estimated Features [d]', 'Total Spent [d]', 'Renuo Velocity', 'Total Spent Incl. Ongoing [d]']
  rows << :separator

  user_ids = [1, 2, 25, 26, 30, 31]

  #weeks = 8
  weeks = 6
  weeks.downto(0) do |weeks_ago|
    rows << calculate_velocity(user_ids, weeks_ago, 1)
  end

  [24, 18, 12, 9, 6, 3, 2, 1].each do |months|
    rows << calculate_velocity(user_ids, months * 4, months * 4)
  end

  table = Terminal::Table.new rows: rows, title: 'Renuo Velocity (Developers Only)'
  rows.each_index { |index| table.align_column(index, :right) }
  puts table

  max_projects = 10
  relevant_projects = find_relevant_projects(user_ids, max_projects)
  relevant_projects.each do |project|
    project_rows = []
    project_rows << ['Weeks Ago', 'Estimation Velocity', 'Estimated [d]', 'Spent [d]', 'Project Velocity', 'Estimated Features [d]', 'Total Spent [d]', 'Renuo Velocity', 'Total Spent Incl. Ongoing [d]']
    project_rows << :separator

    weeks = 6
    weeks.downto(0) do |weeks_ago|
      project_rows << calculate_velocity(user_ids, weeks_ago, 1, project.id)
    end

    [48, 24, 12, 6, 3, 2, 1].each do |months|
      project_rows << calculate_velocity(user_ids, months * 4, months * 4, project.id)
    end

    project_table = Terminal::Table.new rows: project_rows, title: "Project '#{project.name}' Velocity (Developers Only)"
    project_rows.each_index { |index| table.align_column(index, :right) }
    puts project_table
  end
end

def find_relevant_projects(user_ids, max_projects)
  relevant_months = 1
  now = DateTime.now
  start_date = now - now.wday.days - (relevant_months * 4).weeks
  end_date = start_date + (relevant_months * 4).weeks

  issues_this_week = TimeEntry.where(spent_on: start_date..end_date, user_id: user_ids).includes(issue: [:time_entries, :project]).map(&:issue).uniq.reject do |i|
    i.nil? || !i.closed?
  end
  project_time = issues_this_week.map { |i| { issue: i } }.group_by { |i| i[:issue].project }.map { |project, issues| [project, spent_hours(issues, user_ids)] }
  ordered_project_time = project_time.sort_by { |x| -x[1] }
  ordered_project_time.select{|x| x[1].to_f > 30}.map { |x| x[0] }.first(max_projects)
end

def format_days(hours)
  (hours / 8.5).round(1)
end

def calculate_velocity(user_ids, weeks_ago, total_weeks, project_id = nil)
  weekly_planning_estimated_hours, weekly_planning_spent_hours, estimated_feature_hours, spent_hours, spent_hours_including_ongoing = calculate_estimated_and_spent(user_ids, weeks_ago, total_weeks, project_id)

  weeks_ago_display = total_weeks == 1 ? "Sprint #{weeks_ago} weeks ago" : "Last #{total_weeks / 4} months"
  weekly_planning_velocity = weekly_planning_spent_hours.zero? ? 0 : weekly_planning_estimated_hours / weekly_planning_spent_hours
  total_project_velocity = spent_hours.zero? ? 0 : estimated_feature_hours / spent_hours
  total_renuo_velocity = spent_hours_including_ongoing.zero? ? 0 : estimated_feature_hours / spent_hours_including_ongoing


  return weeks_ago_display,
    weekly_planning_velocity.round(3), format_days(weekly_planning_estimated_hours), format_days(weekly_planning_spent_hours),
    total_project_velocity.round(3), format_days(estimated_feature_hours), format_days(spent_hours),
    total_renuo_velocity.round(3), format_days(spent_hours_including_ongoing)
end

def calculate_estimated_and_spent(user_ids, weeks_ago, total_weeks, project_id)
  now = DateTime.now
  start_date = now - now.wday.days - weeks_ago.weeks
  end_date = start_date + total_weeks.weeks

  ignore_issues = [] # 3646?

  issues_this_week = TimeEntry.where(spent_on: start_date..end_date, user_id: user_ids).includes(issue: :time_entries).map(&:issue).uniq.reject do |i|
    i.nil? || ignore_issues.include?(i.id) || !i.closed? || (!project_id.nil? && i.project_id != project_id)
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
  weekly_planning_spent_hours = spent_hours(normal_issues.select { |v| v[:estimated_and_spent] }, user_ids)

  estimated_feature_hours = normal_issues.select { |v| v[:estimated_and_spent] }.select { |v| v[:tracker_name] == 'Feature' }.map { |i| i[:issue] }.map(&:estimated_hours).reduce(:+).to_f
  spent_hours = spent_hours(normal_issues, user_ids)
  spent_hours_including_ongoing = spent_hours(issues_this_week_enhanced, user_ids)

  return weekly_planning_estimated_hours, weekly_planning_spent_hours, estimated_feature_hours, spent_hours, spent_hours_including_ongoing
end

def spent_hours(enhanced_issues, user_ids)
  enhanced_issues.map { |i| i[:issue] }.map { |i| i.time_entries.where(user_id: user_ids).map(&:hours).reduce(:+).to_f }.reduce(:+).to_f
end

main()
