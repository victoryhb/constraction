# %%
from pyvis.network import Network
import networkx as nx
import csv
from config import output_folder
import os
output_fn = os.path.join(output_folder, "output.txt")
from scipy.stats import zscore
# G = nx.Graph()
# %%
net = Network(height="100%", width="60%", notebook=True)
rows = csv.reader(open(output_fn))
target_word = "accuse"
for items in rows:
    bigram, gram1, gram2, score, freq = [i.strip() for i in items]
    for gram in [gram1, gram2]:
        if gram not in net.nodes:
            if gram == target_word:
                val = 20
                net.add_node(gram, label=gram, shape='box', value=val, scaling={"label": {"enabled": True, "min": val}}, color="red")
            else:
                net.add_node(gram, label=gram, shape='box')
    net.add_node(bigram, color="#00ff00", shape='box', value=freq)
    smooth_settings = {"enabled":True, "roundedness": 0.05}
    net.add_edge(gram1, bigram, weight=freq, arrows="to", smooth=smooth_settings)
    net.add_edge(gram2, bigram, weight=freq, arrows="to", smooth=smooth_settings)
# pos = nx.spring_layout(net, k=3)
# nx.draw(net, pos=pos, with_labels=True, font_size=8)
net.show_buttons()
net.show("/Users/yan/Downloads/patterns/output.html")
# %%
