from flask import Flask, request, jsonify
from flask_cors import CORS
from pymongo import MongoClient
import bcrypt

app = Flask(__name__)
CORS(app)
# Connect to MongoDB
client = MongoClient("mongodb+srv://HooFer:Hoofermongodb26101999@cluster0.nlwsh.mongodb.net/?appName=Cluster0")
db = client["drube_cred"]
users_collection = db["users"]

@app.route("/register", methods=["POST"])
def register():
    data = request.json
    username = data.get("username")
    password = data.get("password")

    if not username or not password:
        return jsonify({"message": "Username and password required"}), 400

    # Check if user already exists
    existing_user = users_collection.find_one({"username": username})
    if existing_user:
        return jsonify({"message": "User already exists"}), 409

    # Hash password
    hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())

    # Insert into database
    users_collection.insert_one({
        "username": username,
        "password": hashed_password.decode('utf-8')  # store as string
    })

    return jsonify({"message": "User registered successfully"}), 201

@app.route('/robot/connect', methods=['POST'])
def robot_connect():
    qr_code = request.json.get('qr_code')
    print(f"Received QR code: {qr_code}")  # Debug: Print the received QR code  
    users_collection = db["users_detail"]
    data = users_collection.find_one({"robot_id": qr_code['robot_id']})
    if not data:
        return jsonify({"message": "Robot not found"}), 404
    else:
        return jsonify({"message": "Robot connected successfully", "data": data}), 200
    

@app.route("/login", methods=["POST"])
def login():
    data = request.json
    username = data.get("username")
    password = data.get("password")
    user = users_collection.find_one({"username": username})
    if not user:
        return jsonify({"message": "User not found"}), 404

    stored_password = user["password"].encode('utf-8')

    if bcrypt.checkpw(password.encode('utf-8'), stored_password):
        return jsonify({"message": "Login successful"}), 200
    else:
        return jsonify({"message": "Invalid password"}), 401
    
def serialize_doc(doc):
    doc["_id"] = str(doc["_id"])
    return doc


@app.route("/getall", methods=["GET"])
def get_all_data():
    data = list(users_collection.find())
    serialized_data = [serialize_doc(doc) for doc in data]
    return jsonify(serialized_data)

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)