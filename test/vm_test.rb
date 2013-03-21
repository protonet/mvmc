class VMTest < MiniTest::Unit::TestCase

  def setup
    @example_list_output <<-ELISTOUTPUT
      Id Name                 State
     ----------------------------------
       3 windows8             running
    ELISTOUTPUT
  end

  def test_parsing_list_output
    skip
  end

  def test_parsing_vncdisplay_output
    skip
  end

end
