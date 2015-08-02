require 'rails_helper'

describe 'homepage', type: :feature do
	it 'shows the page' do
		visit '/'
		expect(page).to have_content 'Home'

	end
end
