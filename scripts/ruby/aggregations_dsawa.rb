# encoding: UTF-8

require 'mongo'
include Mongo

host = 'localhost'
port = 27017
db = 'nosql'
collection = 'zipcodes'

connection_info = <<CONNECTION_INFO
Nie podano informacji wszystkich potrzebnych do połączenia się z bazą.
Skrypt może przepytać o wymagane informacje, lub załadować domyślne.
Co zrobić? (d - domyślne) (p - pytaj mnie) (q - wyjdź)
CONNECTION_INFO

if ARGV.size < 4 && ARGV.first != 'd'
  puts connection_info
  case STDIN.gets.chomp
    when 'd'
      true
    when 'p'
      puts 'Podaj nazwę hosta: '
      host = STDIN.gets.chomp
      puts 'Podaj nr portu: '
      port = STDIN.gets.chomp().to_i
      puts 'Podaj nazwę bazy: '
      db = STDIN.gets.chomp
      puts 'Podaj nazwę kolekcji: '
      collection = STDIN.gets.chomp
    else
      exit!
  end
elsif ARGV.size == 4
  host = ARGV.first
  port = ARGV[1].to_i
  db = ARGV[2]
  collection = ARGV.last
end

db = MongoClient.new(host, port, w: 1, wtimeout: 200, j: true).db(db)
zipcodes = db.collection(collection)

puts "Liczba wszystkich wpisów o kodach pocztowych: #{zipcodes.count}"

count_field = 'zipcodes_count'
separator = '------------------------------'

# Ilość kodów pocztowych (wpisów) dla każdego województwa, sortowanie DESC
voivoidships_grouped = zipcodes.aggregate([{ '$group' =>
                                               { :_id => '$wojewodztwo', count_field => { '$sum' => 1 } } },
                                           { '$project' => { :_id => 0, :voivoidship => '$_id', count_field => 1 } },
                                           { '$sort' => { count_field => -1 } }
                                          ])
puts separator
voivoidships_grouped.each { |hash| puts "Województwo: #{hash['voivoidship']}, #{hash[count_field]} wpisów." }

# Średnia ilość wpisów dla miasta wg województw.
cities_avg = zipcodes.aggregate([{ '$group' =>
                                           { :_id => { :wojewodztwo => '$wojewodztwo', :miejsce => '$miejsce' },
                                             count_field => { '$sum' => 1 }
                                           }
                                       },
                                       { '$group' =>
                                           { :_id => '$_id.wojewodztwo', :avg_zipcodes => { '$avg' => '$' + count_field } }
                                       },
                                       { '$sort' => { :avg_zipcodes => -1 } },
                                       { '$project' => { :_id => 0, :avg_zipcodes => 1, :voivoidship => '$_id' } }
                                      ])
puts separator
cities_avg.each do |hash|
  puts "Miasto w województwie: #{hash['voivoidship']}, posiada średnio #{hash['avg_zipcodes'].round(2)} wpisów."
end

# Znalezienie kodów pocztowych zaczynających sie na 84 lub 85, gdzie liczba wpisów większa od 5
zipcodes_regex = zipcodes.aggregate([{ '$match' => { :kod => /8[45]-\d{3}/ } },
                                     { '$group' => { :_id => '$miejsce', count_field => { '$sum' => 1 } } },
                                     { '$match' => { count_field => { '$gt' => 5 } } },
                                     { '$project' => { :_id => 0, :city => '$_id', count_field => 1 } }
                                    ])
puts separator
zipcodes_regex.each { |hash| puts "Miasto: #{hash['city']}, #{hash[count_field]} wpisów." }

# Znalezienie miast Trójmiasta i liczbę ich kodów pocztowych (wpisów), zwracane alfabetycznie.
zipcodes_tricity = zipcodes.aggregate([{ '$match' => { :miejsce => { '$in' => %w(Gdynia Sopot Gdańsk) } } },
                                       { '$group' => { :_id => '$miejsce', count_field => { '$sum' => 1 } } },
                                       { '$project' => { :_id => 0, :city => '$_id', count_field => 1 } },
                                       { '$sort' => { :city => 1 } }
                                      ])
puts separator
zipcodes_tricity.each { |hash| puts "Miasto: #{hash['city']}, #{hash[count_field]} wpisów." }

# Miejsca z największą ilością wpisów o kodach pocztowych w danym województwie.
# Ku zaskoczeniu nie ma Warszawy dla Mazowieckiego :)
# Jest to spowodowane tym, że informacja o Warszawie jest rozdzielona na wiele dzielnic np. "miejsce": "Warszawa (Praga)"
top_voivoidship_places = zipcodes.aggregate([{ '$group' =>
                                                 { :_id => { :wojewodztwo => '$wojewodztwo', :miejsce => '$miejsce' },
                                                   count_field => { '$sum' => 1 }
                                                 }
                                             },
                                             { '$sort' => { count_field => -1 } },
                                             { '$group' =>
                                                 { :_id => '$_id.wojewodztwo',
                                                   :place => { '$first' => '$_id.miejsce' },
                                                   count_field => { '$first' => '$' + count_field }
                                                 }
                                             },
                                             { '$sort' => { :_id => 1 } },
                                             { '$project' =>
                                                 { :_id => 0, :voivoidship => '$_id', :place => 1, count_field => 1 } }
                                            ])
puts separator
top_voivoidship_places.each do |hash|
  puts "W województwie: #{hash['voivoidship']}, najwięcej kodów ma: #{hash['place']} (#{hash[count_field]})."
end

# Gmina z najwiekszą ilością wpisów o kodach pocztowych.
common_county = zipcodes.aggregate([{ '$group' =>
                                        { :_id => { :wojewodztwo => '$wojewodztwo', :kod => '$kod', :gmina => '$gmina' },
                                          count_field => { '$sum' => 1 } }
                                    }, { '$sort' => { count_field => -1 } },
                                    { '$limit' => 1 },
                                    { '$project' =>
                                        { :_id => 0, count_field => 1, :voivoidship => '$_id.wojewodztwo', :county => '$_id.gmina' } }
                                   ]).first
puts separator
puts "Najwięcej wpisów o kodach dotyczy gminy: #{common_county['county']}, w województwie: #{common_county['voivoidship']}"
