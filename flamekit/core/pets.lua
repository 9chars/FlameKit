-- pets.lua (0.15.313, owner 2026-11-20 11:40: "can you add the Pets section and add all the available pets into?"):
-- the game's peaceful animals a companion can be (the Companion Roster's Kind list shows them as its "Pets" section).
-- From the game's template names (tools/gamedata/templates.csv, 2026-11-14): Animal_Wildlife_* and Animal_Baby_*,
-- without fish, flying birds, tests and deprecated ones. { group, name, template GUID }
return {
  { "Pets", "Dog (bright)", "5d9c1829-69fc-4339-8bcc-5e62e63e9a31" },     -- Animal_Wildlife_Dog_01_bright_AG2
  { "Pets", "Dog (dotted)", "74bda2f0-74ab-4bad-851e-2328c808daf0" },     -- Animal_Wildlife_Dog_02_dotted_AG2
  { "Pets", "Dog (dark)", "406d4e1c-594b-4816-8b8d-77cfef1e83bc" },       -- Animal_Wildlife_Dog_03_dark_AG2
  { "Pets", "Dog (black)", "68c37a11-69c9-476b-9117-ef85226a086e" },      -- Animal_Wildlife_Dog_04_black_AG2
  { "Pets", "Dog (white)", "51d37581-38fc-4741-9e4c-1dc85463ec67" },      -- Animal_Wildlife_Dog_05_white_AG2
  { "Pets", "Cat (black)", "1ce5ac27-d8b1-4fa8-92db-f568994d080f" },      -- Animal_Wildlife_Cat_01_black_AG2
  { "Pets", "Cat (striped)", "60065215-15ca-424c-9bc3-5665685fed60" },    -- Animal_Wildlife_Cat_02_striped_AG2
  { "Pets", "Cat (bright)", "8d2e50d2-ed98-4231-9846-ca1b7fb69041" },     -- Animal_Wildlife_Cat_03_bright_AG2
  { "Pets", "Goat", "1a2d46a7-cdc5-4592-829e-c13ebf0e14ae" },             -- Animal_Wildlife_T1_Goat_AG2
  { "Pets", "Mountain goat", "397fe913-9307-4001-83ee-ae8a8074c0b7" },    -- Animal_Wildlife_T5_Goat_Coldheights_Variation_Mountaingoat
  { "Pets", "Bunny", "7e389a60-f74b-4133-a5aa-68e91623985c" },            -- Animal_Wildlife_T2_Bunny_AG2
  { "Pets", "Bunny (Cold Heights)", "1b8afedd-e02c-4746-88ff-c4367b53fa8e" },  -- Animal_Wildlife_Bunny_Coldheights_Variation
  { "Pets", "Cat-deer", "b562b0b2-6779-4172-ab01-06136a1b6693" },         -- Animal_Wildlife_T2_Catdeer_AG2
  { "Pets", "Turkey", "5b609722-0dae-444b-b96c-283054a05495" },           -- Animal_Wildlife_T3_Bird_Turkey_AG2
  { "Pets", "Desert bird", "4757dca8-d76b-4d1c-8215-cb1e7ee533a2" },      -- Animal_Wildlife_T4_Bird_Desert_AG2
  { "Pets", "Yak", "ae8c6943-f581-43ed-8e66-d1b07b2ea4f5" },              -- Animal_Wildlife_T5_Yak_AG2
  { "Pets", "Capybara", "df787789-d005-42e8-a18f-f4fe2e5d2e42" },         -- Animal_Wildlife_T6_Capybara_AG2
  { "Pets", "Baby goat", "f105a553-de24-444b-b7e7-0abe250e0b2a" },        -- Animal_Baby_T1_Goat
  { "Pets", "Baby mountain goat", "8e24c10f-2d19-4ed6-9875-68f87fa91580" },  -- Animal_Baby_T5_Mountaingoat
  { "Pets", "Baby bunny", "4d81f8c5-a230-406c-8bb1-df9f6e66cf2d" },       -- Animal_Baby_T2_Bunny
  { "Pets", "Baby cat-deer", "072eed62-d51e-4fb6-a899-589aed709f84" },    -- Animal_Baby_T2_CatDeer
  { "Pets", "Baby turkey", "042266d3-e887-4ff4-9d22-dc9338aa76be" },      -- Animal_Baby_T3_Turkey
  { "Pets", "Baby desert bird", "3f5fe59f-7f28-44ec-80e1-d946f6028d7d" },  -- Animal_Baby_T4_Bird_Desert
  { "Pets", "Baby sanddigger", "fc546ff6-6117-46d6-b3c2-fdf97c47b7a0" },  -- Animal_Baby_T4_Sanddigger
  { "Pets", "Baby yak", "e8b4ebb2-3dec-4a2a-b6ed-d6116cd53918" },         -- Animal_Baby_T5_Yak
  { "Pets", "Baby capybara", "7a5757d8-2bc0-403e-a556-92f6c39c50f7" },    -- Animal_Baby_T6_Capybara
}
