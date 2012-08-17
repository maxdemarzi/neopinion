require 'rubygems'
require 'neography'
require 'engtagger'

AVERAGE_START_POSITION = 5
MAXIMUM_GAP = 3

@neo = Neography::Rest.new
@tagger = EngTagger.new 

# Each node keeps track of all sentences that it is a part of using a 
# sentence identiﬁer (SID) along with its position of occurrence in that sentence (PID). 
# (A1:10-16) Each node will thus carry a 
# 

# Create the graph
# node properties:
# - pri (Positional Reference Information) which is a list of {SID:PID} pairs
#   - sid (sentence identiﬁer) 
#   - pid (position of occurrence identifier)
# - vsn (valid start node)
# - ven (valid end node)
# 
def create_graph
  sentences = ["My phone calls drop frequently with the iPhone.", 
               "Great device, but the calls drop too frequently."]
  
  word_hash = Hash.new { |hash, key| hash[key] = [] }
  
  sentences.each_with_index do |sentence, sentence_index|
    word_path = []
    tokens = split_sentence(sentence) 
    max = tokens.size

    tokens.each_with_index do |token, token_index|
      is_end_node = valid_end_node(token)
      properties = token.merge({:ven => is_end_node})
      word_path <<  @neo.create_unique_node("word_index", "token", token[:word], properties)

      node_id = get_node_id(word_path[token_index])
      word_hash[node_id] << "#{sentence_index}:#{token_index}"

      @neo.add_node_to_index("word_tag", "tag", token[:tag], node_id) 
      
      if token_index >= 1 && token_index <= max
        rel = @neo.create_relationship("co_occurence", word_path[token_index - 1], word_path[token_index])
      end 
    end
  end         

  word_hash.each do |key, value|
    node_id = key
    properties = {:vsn => valid_start_node(value), :pri => value }
    @neo.set_node_properties(node_id, properties)
    @neo.add_node_to_index("vsn_index", "vsn", "true", node_id) if properties[:vsn]
  end

end  

# Split a sentence by part of speech
# return lowercase word and general part of speech
# 
def split_sentence(sentence)
  @tagger.get_readable(sentence).downcase.split(' ').collect do |w| 
      {  
         :word => w.split('/')[0], 
         :tag => w.split('/')[1][0..1] 
      }
   end 
end

# Valid start nodes are nodes that have an average starting position
# less than the parameter passed in.
#
def valid_start_node(positions, avg_start_position = AVERAGE_START_POSITION)
  positions.collect{|p| p.split(':')[1].to_f }.inject{ |sum, el| sum + el } / positions.size <= avg_start_position
end

# Valid end nodes are periods, commas and coordinating conjunctions (and, but).
#
def valid_end_node(token)
  ["pp", "cc"].include? token[:tag]
end

# Gets the node_id of a node
#
def get_node_id(node)
  node["self"].split('/').last
end


def get_valid_sentences
  @neo = Neography::Rest.new
  cypher = "START vq=node:vsn_index(vsn='true'), vs =node:word_tag('tag:(pp OR cc)')
            MATCH path = vq -[:co_occurence*2..10]-> vs
            RETURN distinct extract(n in nodes(path) : n.word),
                            extract(n in nodes(path) : n.tag),
                            extract(n in nodes(path) : n.pri),
                            LENGTH(path)  "
  result = @neo.execute_query(cypher)["data"]
end

# r(q, s), is the number of overlapping sentences covered by this path,
def score_sentences(sentences)
 # sentence_scores = Hash.new
  sentences.each_with_index do |s,i|
    sids =  s[2].collect{|a| Hash[a.collect{|b| b.split(':')}]}
    # [{"0"=>"6", "1"=>"4"}, {"0"=>"2", "1"=>"5"}, {"0"=>"3", "1"=>"6"}, {"1"=>"7"}, {"0"=>"4", "1"=>"8"}, {"0"=>"5"}, {"0"=>"6", "1"=>"4"}, {"0"=>"7"}, {"0"=>"8", "1"=>"9"}]

    (sids.size - 1).times do |i|
      sids[i].merge!(sids[i+1]) { |key, v1, v2| (v1.to_i - v2.to_i).abs < MAXIMUM_GAP ? true : false }
    end
    #{"0"=>false, "1"=>true}
    #{"0"=>true, "1"=>true}
    #{"0"=>"3", "1"=>true}
    #{"1"=>true, "0"=>"4"}
    #{"0"=>true, "1"=>"8"}
    #{"0"=>true, "1"=>"4"}
    #{"0"=>true, "1"=>"4"}
    #{"0"=>true, "1"=>"9"}

    sids.reverse!
    sids.delete_at(0)
    (sids.size - 1).times do |i|
      sids[0].merge!(sids[i+1]) { |key, v1, v2| (v1 == true && v2 == true) ? true : false }
    end

    sids[0].delete_if {|key, value| value == false }

   # sentence_scores[s] = (1.0/s[3]) * sids[0].size
    sentences[i] << (1.0/s[3]) * sids[0].size
  end
  sentences
end

def test
  sentences = get_valid_sentences
  puts score_sentences(sentences).sort! {|x,y| y[4] <=> x[4] }.collect{|s| "#{s[4]} : #{s[0].join(' ') }"}
end