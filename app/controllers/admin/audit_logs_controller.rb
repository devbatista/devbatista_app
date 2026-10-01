module Admin
  class AuditLogsController < ApplicationController
    PER_PAGE = 50

    def index
      authorize AuditLog
      logs = policy_scope(AuditLog).includes(:user).recent
      logs = logs.where(user_id: params[:user_id]) if params[:user_id].present?
      logs = logs.where(area: params[:area]) if params[:area].present?
      logs = logs.where(action: params[:event]) if params[:event].present?
      logs = logs.where(created_at: period_range) if params[:period].present?

      @page = [ params[:page].to_i, 1 ].max
      @total = logs.count
      @logs = logs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
      @pages = (@total / PER_PAGE.to_f).ceil
      @users = User.by_name
    end

    private

    def period_range
      case params[:period]
      when "hoje" then Time.current.all_day
      when "7d" then 7.days.ago..Time.current
      when "30d" then 30.days.ago..Time.current
      else ..Time.current
      end
    end
  end
end
