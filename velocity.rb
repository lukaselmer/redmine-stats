require 'terminal-table'

class RedmineVelocity
  def initialize
    @developer_ids = [1, 2, 25, 26, 30, 31, 9]
    @all_table_data = []
    @csv_path = ENV['CSV_PATH']
    raise 'Please supply a valid CSV_PATH as env variable' if @csv_path.blank?
  end

  def print_table(title, rows)
    table = Terminal::Table.new rows: rows, title: title
    rows.each_index { |index| table.align_column(index, :right) }
    puts table

    @all_table_data << ([title] + rows)
  end

  def generate_csv
    CSV.open(@csv_path, 'wb') do |csv|
      first = true
      @all_table_data.each do |row|
        csv << row if first || row[1].is_a?(Numeric)
        first = false
      end
    end
  end

  def main
    user_ids = @developer_ids
    overview(user_ids)
    projects(user_ids, 25)
    user_ids.each do |user_id|
      overview([user_id], User.find(user_id))
      projects([user_id], 20, User.find(user_id))
    end
    generate_csv
  end

  def projects(user_ids, max_projects, developer = nil)
    relevant_projects = find_relevant_projects(user_ids, max_projects)
    relevant_projects.each do |project|
      project_rows = []
      project_rows << ['Weeks Ago', 'Estimation Velocity', 'Estimated [d]', 'Spent [d]', 'Project Velocity', 'Estimated Features [d]', 'Total Spent [d]', 'Renuo Velocity', 'Total Spent Incl. Ongoing [d]']
      project_rows << :separator

      weeks = 6
      weeks.downto(0) do |weeks_ago|
        project_rows << calculate_velocity(user_ids, weeks_ago, 1, project.id, developer)
      end

      [48, 12, 6, 3, 2, 1].each do |months|
        project_rows << calculate_velocity(user_ids, months * 4, months * 4, project.id, developer)
      end

      name = developer ? "#{developer.firstname} #{developer.lastname}" : 'Developers Only'
      print_table("Project '#{project.name}' Velocity (#{name})", project_rows)
    end
  end

  def overview(user_ids, developer = nil)
    rows = []
    rows << ['Weeks Ago', 'Estimation Velocity', 'Estimated [d]', 'Spent [d]', 'Project Velocity', 'Estimated Features [d]', 'Total Spent [d]', 'Renuo Velocity', 'Total Spent Incl. Ongoing [d]']
    rows << :separator

    weeks = 6
    weeks.downto(0) do |weeks_ago|
      rows << calculate_velocity(user_ids, weeks_ago, 1, nil, developer)
    end

    [18, 12, 9, 6, 3, 2, 1].each do |months|
      rows << calculate_velocity(user_ids, months * 4, months * 4, nil, developer)
    end

    name = developer ? "#{developer.firstname} #{developer.lastname}" : 'Developers Only'
    print_table("Renuo Velocity (#{name})", rows)
  end

  def find_relevant_projects(user_ids, max_projects)
    relevant_months = 6
    now = DateTime.now
    start_date = now - now.wday.days - (relevant_months * 4).weeks
    end_date = start_date + (relevant_months * 4).weeks

    issues_this_week = TimeEntry.where(spent_on: start_date..end_date, user_id: user_ids).includes(issue: [:time_entries, :project]).map(&:issue).uniq.reject do |i|
      i.nil? || !i.closed?
    end
    project_time = issues_this_week.map { |i| { issue: i } }.group_by { |i| i[:issue].project }.map { |project, issues| [project, spent_hours(issues, user_ids)] }
    ordered_project_time = project_time.sort_by { |x| -x[1] }
    puts "Project time: #{ ordered_project_time.map { |x| [x[0].name, x[1].to_f.round(1)].join(': ') }.join(', ')}"
    ordered_project_time.select { |x| x[1].to_f > 40 }.map { |x| x[0] }.first(max_projects)
  end

  def format_days(hours)
    (hours / 8.5).round(1)
  end

  def calculate_velocity(user_ids, weeks_ago, total_weeks, project_id, developer)
    weekly_planning_estimated_hours, weekly_planning_spent_hours, estimated_feature_hours, spent_hours, spent_hours_including_ongoing =
      calculate_estimated_and_spent(user_ids, weeks_ago, total_weeks, project_id, developer)

    weeks_ago_display = total_weeks == 1 ? "Sprint #{weeks_ago} weeks ago" : "Last #{total_weeks / 4} months"
    weekly_planning_velocity = weekly_planning_spent_hours.zero? ? 0 : weekly_planning_estimated_hours / weekly_planning_spent_hours
    total_project_velocity = spent_hours.zero? ? 0 : estimated_feature_hours / spent_hours
    total_renuo_velocity = spent_hours_including_ongoing.zero? ? 0 : estimated_feature_hours / spent_hours_including_ongoing


    return weeks_ago_display,
      weekly_planning_velocity.round(3), format_days(weekly_planning_estimated_hours), format_days(weekly_planning_spent_hours),
      total_project_velocity.round(3), format_days(estimated_feature_hours), format_days(spent_hours),
      total_renuo_velocity.round(3), format_days(spent_hours_including_ongoing)
  end

  def calculate_estimated_and_spent(user_ids, weeks_ago, total_weeks, project_id, developer)
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
        main_developer_id: main_issue_developer(v),
        ongoing: v.custom_field_value(ongoing) == '1',
        sprint: v.custom_field_value(sprint).try(:to_date),
        issue: v,
        tracker_name: v.tracker.name,
        estimated_and_spent: !v.estimated_hours.to_f.zero? && !v.spent_hours.to_f.zero?
      }
    }
    issues_this_week_enhanced = issues_this_week_enhanced.select { |v| v[:main_developer_id] == developer.id } if developer

    normal_issues = issues_this_week_enhanced.select { |v| !v[:ongoing] }

    # This is relevant for the weekly planning. Include the time of all involved people.
    # E.g. if the test manager needs 1 hour for testing a feature, this time should be included in the estimation.
    weekly_planning_estimated_hours = normal_issues.select { |v| v[:estimated_and_spent] }.map { |i| i[:issue] }.map(&:estimated_hours).reduce(:+).to_f
    weekly_planning_spent_hours = spent_hours(normal_issues.select { |v| v[:estimated_and_spent] })

    estimated_feature_hours = normal_issues.select { |v| v[:estimated_and_spent] }.select { |v| v[:tracker_name] == 'Feature' }.map { |i| i[:issue] }.map(&:estimated_hours).reduce(:+).to_f
    # This is relevant for calculating the estimated deadline.
    # E.g. it doesn't matter for this if the test manager needs time to test an issue since only developer hours need to be planned.
    spent_hours = spent_hours(normal_issues, @developer_ids)
    spent_hours_including_ongoing = spent_hours(issues_this_week_enhanced, @developer_ids)

    return weekly_planning_estimated_hours, weekly_planning_spent_hours, estimated_feature_hours, spent_hours, spent_hours_including_ongoing
  end

  def main_issue_developer(issue)
    issue.time_entries.to_a.group_by(&:user_id).map { |k, v| [k, v.sum(&:hours)] }.max_by { |x| x[1] }[0]
  end

  def spent_hours(enhanced_issues, user_ids = nil)
    enhanced_issues.map { |i| i[:issue] }.map do |i|
      te = i.time_entries
      te = te.where(user_id: user_ids) if user_ids
      te.map(&:hours).reduce(:+).to_f
    end.reduce(:+).to_f
  end
end

RedmineVelocity.new.main()
