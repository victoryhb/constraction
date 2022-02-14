import os
# import mining
import importlib
# importlib.reload(mining)
import db_manager

json_path = "/Users/yan/Downloads/patterns/json_transformed/merge-dep-supersenses1000.json"
output_folder = "/Users/yan/Downloads/patterns/json_transformed/"
os.makedirs(output_folder, exist_ok=True)

db_path = os.path.join(output_folder, "db.sqlite3")
dm = db_manager.DBManager(db_path)
dm.create_database()
# mining.mine_patterns(json_path, output_folder, None, create_database=True)
