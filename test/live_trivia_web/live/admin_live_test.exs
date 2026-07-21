defmodule LiveTriviaWeb.AdminLiveTest do
  use ExUnit.Case, async: true

  alias LiveTriviaWeb.AdminLive

  test "PT-BR preset trivias have complete playable question sets" do
    presets = AdminLive.preset_trivias()

    titles = Enum.map(presets, & &1.title)

    assert length(presets) == 3
    assert Enum.any?(titles, &String.starts_with?(&1, "História"))
    assert "Geografia" in titles
    assert "Esportes" in titles

    for preset <- presets do
      assert is_binary(preset.title)
      assert is_binary(preset.description)
      assert length(preset.questions) == 8

      for question <- preset.questions do
        assert is_binary(question.question)
        assert is_binary(question.answer)
        assert length(question.hints) == 5
        assert Enum.all?(question.hints, &(is_binary(&1) and String.trim(&1) != ""))
      end
    end
  end

  test "preset_questions returns the selected preset questions" do
    for preset <- AdminLive.preset_trivias() do
      assert AdminLive.preset_questions(preset.id) == preset.questions
    end

    assert AdminLive.preset_questions("missing") == nil
  end
end
