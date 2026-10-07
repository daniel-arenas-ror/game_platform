module Admin
  class DashboardController < BaseController
    def show
      @stats = AdminStats.new(range: params[:range])
    end
  end
end
